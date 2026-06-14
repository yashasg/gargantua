import Foundation

/// Routes an on-demand "Explain deeper" request to whichever provider the user
/// selected (`DeeperExplainProvider`). Keeps the explanation controller free of
/// provider-specific knowledge — it just asks this service to deepen a result.
@MainActor
public final class DeeperExplanationService {
    private let cloud: CloudAIService
    private let claudeCode: ClaudeCodeDeeperExplainer
    private let providerPreference: () -> DeeperExplainProvider

    public init(
        cloud: CloudAIService,
        claudeCode: ClaudeCodeDeeperExplainer = ClaudeCodeDeeperExplainer(),
        providerPreference: @escaping () -> DeeperExplainProvider = { DeeperExplainProvider.stored() }
    ) {
        self.cloud = cloud
        self.claudeCode = claudeCode
        self.providerPreference = providerPreference
    }

    /// Run a deeper explanation through the currently selected provider.
    public func explainDeeper(result: ScanResult, rule: ScanRule) async throws -> AIExplanation {
        switch providerPreference() {
        case .cloud:
            return try await cloud.explain(result: result, rule: rule)
        case .claudeCode:
            return try await claudeCode.explain(result: result, rule: rule)
        }
    }

    /// Whether the currently selected provider is configured and ready. The
    /// sheet uses this to decide whether to offer the "Explain deeper" button.
    public func isAvailable() -> Bool {
        switch providerPreference() {
        case .cloud:
            return cloud.canExplainDeeper()
        case .claudeCode:
            return claudeCode.canExplainDeeper()
        }
    }
}
