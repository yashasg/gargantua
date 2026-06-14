import Foundation
import OSLog

private let oneShotLogger = Logger(
    subsystem: "com.gargantua.core",
    category: "ClaudeCodeOneShotRunner"
)

/// Runs the user's `claude` CLI as a single non-interactive completion:
/// `claude -p "<prompt>" --output-format text --max-turns 1` with an empty,
/// strict MCP config so the CLI doesn't probe servers or attempt agentic tool
/// discovery. Captures stdout and maps exit codes / timeouts to typed errors.
///
/// Shared by every one-shot Claude Code consumer (file-organization proposals,
/// deeper explanations) so the subprocess plumbing — async pipe draining,
/// cancellation, timeout, single-resume continuation — lives in exactly one
/// place.
public struct ClaudeCodeOneShotRunner: @unchecked Sendable {
    private let processFactory: @Sendable () -> Process
    private let fileManager: FileManager
    private let timeoutSeconds: Int

    public init(
        processFactory: @Sendable @escaping () -> Process = { Process() },
        fileManager: FileManager = .default,
        timeoutSeconds: Int = 240
    ) {
        self.processFactory = processFactory
        self.fileManager = fileManager
        self.timeoutSeconds = timeoutSeconds
    }

    /// Run one completion and return stdout. `model` may be empty to use the
    /// CLI's default model.
    public func run(executable: URL, prompt: String, model: String) async throws -> String {
        // Stop claude from probing MCP servers, allowed tools, or any other
        // agentic discovery — we want a one-shot completion only. A minimal
        // empty MCP config + --strict-mcp-config short-circuits the search.
        let emptyMCPConfig = try writeEmptyMCPConfig()
        defer { try? fileManager.removeItem(at: emptyMCPConfig) }

        var arguments = [
            "-p",
            prompt,
            "--output-format",
            "text",
            "--max-turns",
            "1",
            "--mcp-config",
            emptyMCPConfig.path,
            "--strict-mcp-config",
        ]
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            arguments += ["--model", trimmedModel]
        }

        oneShotLogger.error(
            "claude one-shot start: \(executable.path, privacy: .public) prompt-len=\(prompt.count) model=\(trimmedModel, privacy: .public)"
        )

        let processBox = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = processFactory()
                processBox.process = process
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let stdoutBuffer = DataBuffer()
                let stderrBuffer = DataBuffer()
                let resumed = AtomicFlag()

                let pipes = SubprocessPipes(stdout: stdoutPipe, stderr: stderrPipe)
                let buffers = SubprocessBuffers(stdout: stdoutBuffer, stderr: stderrBuffer)
                configure(
                    process: process,
                    executable: executable,
                    arguments: arguments,
                    pipes: pipes
                )
                attachReadabilityHandlers(pipes: pipes, buffers: buffers)
                process.terminationHandler = makeTerminationHandler(
                    pipes: pipes,
                    buffers: buffers,
                    resumed: resumed,
                    continuation: continuation
                )
                spawnTimeoutWatcher(process: process, resumed: resumed, continuation: continuation)

                do {
                    try process.run()
                } catch {
                    if resumed.takeIfFalse() {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            processBox.process?.terminate()
        }
    }

    // MARK: - Subprocess helpers

    private func configure(
        process: Process,
        executable: URL,
        arguments: [String],
        pipes: SubprocessPipes
    ) {
        process.executableURL = executable
        process.arguments = arguments
        // Close stdin so claude doesn't sit waiting for an interactive
        // turn that will never come.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipes.stdout
        process.standardError = pipes.stderr
    }

    /// Drain the pipes asynchronously while the process runs. Otherwise
    /// a >16KB response (Sonnet on a busy folder hits this fast) fills
    /// the pipe buffer, the CLI blocks on write, and the process never
    /// exits.
    private func attachReadabilityHandlers(pipes: SubprocessPipes, buffers: SubprocessBuffers) {
        pipes.stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffers.stdout.append(chunk)
            }
        }
        pipes.stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffers.stderr.append(chunk)
            }
        }
    }

    private func makeTerminationHandler(
        pipes: SubprocessPipes,
        buffers: SubprocessBuffers,
        resumed: AtomicFlag,
        continuation: CheckedContinuation<String, Error>
    ) -> @Sendable (Process) -> Void {
        return { proc in
            pipes.stdout.fileHandleForReading.readabilityHandler = nil
            pipes.stderr.fileHandleForReading.readabilityHandler = nil
            if let remaining = try? pipes.stdout.fileHandleForReading.readToEnd() {
                buffers.stdout.append(remaining)
            }
            if let remaining = try? pipes.stderr.fileHandleForReading.readToEnd() {
                buffers.stderr.append(remaining)
            }

            guard resumed.takeIfFalse() else { return }
            let stdout = buffers.stdout.snapshot()
            let stderr = buffers.stderr.snapshot()
            let status = proc.terminationStatus
            let reason = proc.terminationReason
            oneShotLogger.error(
                "claude one-shot exit: status=\(status) reason=\(reason.rawValue) stdout-bytes=\(stdout.count) stderr-bytes=\(stderr.count)"
            )
            if status == 0, reason == .exit {
                if let text = String(data: stdout, encoding: .utf8), !text.isEmpty {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: ClaudeCodeOneShotError.emptyResponse)
                }
            } else {
                let stderrString = String(data: stderr, encoding: .utf8) ?? ""
                oneShotLogger.error(
                    "claude CLI stderr: \(stderrString.prefix(600), privacy: .public)"
                )
                continuation.resume(throwing: ClaudeCodeOneShotError.cliFailed(
                    exitCode: Int(status),
                    stderr: stderrString
                ))
            }
        }
    }

    private func spawnTimeoutWatcher(
        process: Process,
        resumed: AtomicFlag,
        continuation: CheckedContinuation<String, Error>
    ) {
        let seconds = timeoutSeconds
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            if process.isRunning, resumed.takeIfFalse() {
                oneShotLogger.error(
                    "claude CLI timed out after \(seconds)s — terminating subprocess"
                )
                process.terminate()
                continuation.resume(throwing: ClaudeCodeOneShotError.timedOut(seconds: seconds))
            }
        }
    }

    private func writeEmptyMCPConfig() throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("gargantua-oneshot-mcp-\(UUID().uuidString).json")
        try Data(#"{"mcpServers":{}}"#.utf8).write(to: url)
        return url
    }
}

/// Failure modes of a one-shot `claude` invocation. Callers map these onto
/// their own feature-specific error types for user-facing messages.
public enum ClaudeCodeOneShotError: Error, Equatable {
    case cliFailed(exitCode: Int, stderr: String)
    case emptyResponse
    case timedOut(seconds: Int)
}

/// Shared mutable handle to the in-flight subprocess so the cancel
/// callback can reach it from outside the continuation closure.
private final class ProcessBox: @unchecked Sendable {
    var process: Process?
}

private struct SubprocessPipes {
    let stdout: Pipe
    let stderr: Pipe
}

private struct SubprocessBuffers {
    let stdout: DataBuffer
    let stderr: DataBuffer
}

/// One-shot flag used to make sure exactly one path (success, error,
/// timeout, cancel) resumes the continuation. Without this, racing the
/// terminationHandler against the timeout Task can crash.
private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flipped = false

    /// Atomically flip the flag from false → true. Returns true if THIS
    /// caller did the flip; false if someone got there first.
    func takeIfFalse() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if flipped { return false }
        flipped = true
        return true
    }
}

/// Lock-guarded `Data` buffer for accumulating subprocess output from
/// `FileHandle.readabilityHandler` (which fires on a background queue).
private final class DataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
