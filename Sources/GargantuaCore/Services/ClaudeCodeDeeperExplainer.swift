import Foundation

/// Deeper, on-demand explanation routed through the user's local `claude` CLI
/// (their Claude subscription) instead of the metered Anthropic API. Reuses the
/// Claude Code agent's configured CLI path + model, builds the same prose
/// explanation prompt the Cloud provider uses, and runs it one-shot.
public struct ClaudeCodeDeeperExplainer: Sendable {
    private let configurationStore: ClaudeCodeAgentConfigurationStore
    private let cliResolver: ClaudeCodeCLIResolver
    private let runner: ClaudeCodeOneShotRunner

    public init(
        configurationStore: ClaudeCodeAgentConfigurationStore = ClaudeCodeAgentConfigurationStore(),
        cliResolver: ClaudeCodeCLIResolver = ClaudeCodeCLIResolver(),
        runner: ClaudeCodeOneShotRunner = ClaudeCodeOneShotRunner()
    ) {
        self.configurationStore = configurationStore
        self.cliResolver = cliResolver
        self.runner = runner
    }

    public func explain(result: ScanResult, rule _: ScanRule) async throws -> AIExplanation {
        let configuration = configurationStore.load()
        guard configuration.isEnabled else {
            throw ClaudeCodeDeeperExplainError.agentNotEnabled
        }
        let executable = try cliResolver.resolve(configuration: configuration)

        // Metadata-only redaction (no file contents) — the deeper explanation
        // is advisory and the CLI shouldn't receive raw file bodies.
        let items = try CloudAIRedactor.items(from: [result], allowsFileContents: false)
        guard let item = items.first else {
            throw ClaudeCodeDeeperExplainError.agentNotEnabled
        }
        let prompt = try CloudAIPromptBuilder.explanationPrompt(item: item)

        let text: String
        do {
            text = try await runner.run(
                executable: executable,
                prompt: prompt,
                model: configuration.selectedModel
            )
        } catch let error as ClaudeCodeOneShotError {
            throw ClaudeCodeDeeperExplainError(oneShot: error)
        }

        return AIExplanation(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .claudeCode
        )
    }

    /// Whether the Claude Code provider can run a deeper explanation right now:
    /// the agent is enabled and its CLI resolves.
    public func canExplainDeeper() -> Bool {
        let configuration = configurationStore.load()
        guard configuration.isEnabled else { return false }
        return (try? cliResolver.resolve(configuration: configuration)) != nil
    }
}

public enum ClaudeCodeDeeperExplainError: Error, LocalizedError, Equatable {
    case agentNotEnabled
    case cliFailed(exitCode: Int, stderr: String)
    case emptyResponse
    case timedOut(seconds: Int)

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
            return "claude CLI didn't respond within \(seconds)s. Try Cloud, or check that the CLI is logged in."
        }
    }
}
