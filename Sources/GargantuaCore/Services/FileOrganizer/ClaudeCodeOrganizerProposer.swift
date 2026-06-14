import Foundation

/// File-organization proposer routed through the user's `claude` CLI
/// (the same one the Claude Code agent feature uses). Spawns a one-shot
/// `claude -p "<prompt>" --output-format text --max-turns 1` subprocess,
/// captures stdout, and feeds the response into the existing
/// `CloudOrganizerProposer.parseResponse` parser.
///
/// Reuses the agent's configuration (CLI path + selectedModel) so a
/// user who has Claude Code set up doesn't need a separate Anthropic
/// API key for the organizer.
public struct ClaudeCodeOrganizerProposer: @unchecked Sendable {
    private let configurationStore: ClaudeCodeAgentConfigurationStore
    private let cliResolver: ClaudeCodeCLIResolver
    private let processFactory: @Sendable () -> Process
    private let now: @Sendable () -> Date
    private let fileManager: FileManager
    private let timeoutSeconds: Int

    public init(
        configurationStore: ClaudeCodeAgentConfigurationStore = ClaudeCodeAgentConfigurationStore(),
        cliResolver: ClaudeCodeCLIResolver = ClaudeCodeCLIResolver(),
        processFactory: @Sendable @escaping () -> Process = { Process() },
        now: @Sendable @escaping () -> Date = { Date() },
        fileManager: FileManager = .default,
        timeoutSeconds: Int = 240
    ) {
        self.configurationStore = configurationStore
        self.cliResolver = cliResolver
        self.processFactory = processFactory
        self.now = now
        self.fileManager = fileManager
        self.timeoutSeconds = timeoutSeconds
    }

    public func propose(sourceFolder: URL) async throws -> OrganizationProposal {
        let configuration = configurationStore.load()
        guard configuration.isEnabled else {
            throw ClaudeCodeOrganizerError.agentNotEnabled
        }
        let executable = try cliResolver.resolve(configuration: configuration)

        let listing = try CloudOrganizerProposer.listFolder(at: sourceFolder, fileManager: fileManager)
        let clusters = OrganizerClusterer.cluster(listing)
        let prompt = CloudOrganizerProposer.buildPrompt(
            folderName: sourceFolder.lastPathComponent,
            clusters: clusters
        )

        let runner = ClaudeCodeOneShotRunner(
            processFactory: processFactory,
            fileManager: fileManager,
            timeoutSeconds: timeoutSeconds
        )
        let output: String
        do {
            output = try await runner.run(
                executable: executable,
                prompt: prompt,
                model: configuration.selectedModel
            )
        } catch let error as ClaudeCodeOneShotError {
            throw ClaudeCodeOrganizerError(oneShot: error)
        }

        return try CloudOrganizerProposer.parseResponse(
            text: output,
            sourceFolder: sourceFolder,
            clusters: clusters,
            backend: .cloud,
            generatedAt: now()
        )
    }
}

public enum ClaudeCodeOrganizerError: Error, LocalizedError, Equatable {
    case agentNotEnabled
    case cliFailed(exitCode: Int, stderr: String)
    case emptyResponse
    case timedOut(seconds: Int)

    /// Map a shared one-shot runner failure onto the organizer's own error
    /// surface so callers and tests keep seeing organizer-specific cases.
    init(oneShot: ClaudeCodeOneShotError) {
        switch oneShot {
        case .cliFailed(let exitCode, let stderr):
            self = .cliFailed(exitCode: exitCode, stderr: stderr)
        case .emptyResponse:
            self = .emptyResponse
        case .timedOut(let seconds):
            self = .timedOut(seconds: seconds)
        }
    }

    public var errorDescription: String? {
        switch self {
        case .agentNotEnabled:
            return "Claude Code agent is not enabled. Turn it on in Settings → AI → Claude Code Agent."
        case .cliFailed(let exitCode, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "claude CLI exited with status \(exitCode)."
            }
            return "claude CLI failed: \(trimmed)"
        case .emptyResponse:
            return "claude CLI returned no output."
        case .timedOut(let seconds):
            return "claude CLI didn't respond within \(seconds)s. Try Cloud or On-device rules, or check that the CLI is logged in."
        }
    }
}
