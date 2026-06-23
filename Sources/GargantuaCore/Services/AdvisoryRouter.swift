import Foundation

/// Routes a batch advisory request to whichever engine is assigned to the
/// `.advisory` job (`AIEngineAssignments`). The "Review Advisories" and
/// "Suspicious Triage" surfaces both flow through here, so a user can point
/// advisories at the local model, the Cloud API, or a CLI agent — the same
/// roster the inline "Why?" explanation honors.
///
/// Mirrors `ExplanationRouter`. The local path delegates to
/// `LocalAIService.advisory`, which owns model lifecycle, the YAML fallback,
/// and the safety invariant. The remote paths (Cloud / Claude Code / Codex)
/// reuse each provider's single-item `explain` — an advisory is a per-item
/// rationale plus the result's existing safety, exactly what those engines
/// already produce — wrapping each explanation as a `ScanResultAdvisory` and
/// falling back to the YAML rule on a per-item failure.
@MainActor
public final class AdvisoryRouter {
    private let local: LocalAIService
    private let cloud: CloudAIService
    private let claudeCode: ClaudeCodeDeeperExplainer
    private let codex: CodexExplainer
    private let assignment: (AIUseCase) -> AIEngineID

    public init(
        local: LocalAIService,
        cloud: CloudAIService,
        claudeCode: ClaudeCodeDeeperExplainer = ClaudeCodeDeeperExplainer(),
        codex: CodexExplainer = CodexExplainer(),
        assignment: @escaping (AIUseCase) -> AIEngineID = { AIEngineAssignments.engine(for: $0) }
    ) {
        self.local = local
        self.cloud = cloud
        self.claudeCode = claudeCode
        self.codex = codex
        self.assignment = assignment
    }

    /// Produce advisories for the supplied results using the engine assigned to
    /// `.advisory`. Eligibility (review-tier only, or every non-protected item
    /// when `includeNonReview` is set) is applied consistently across engines.
    ///
    /// Throws `AdvisoryRouterError.engineUnavailable` when a remote engine is
    /// assigned but not configured, so the sheet surfaces a clear, actionable
    /// failure instead of silently degrading to rule text.
    public func advisory(
        for results: [ScanResult],
        rules: [String: ScanRule],
        includeNonReview: Bool = false
    ) async throws -> [ScanResultAdvisory] {
        switch assignment(.advisory) {
        case .template, .mlx:
            // LocalAIService runs whichever local engine AIEngineAssignments
            // mirrored into AIEnginePreference (Template or MLX).
            return try await local.advisory(
                for: results,
                rules: rules,
                includeNonReview: includeNonReview
            )
        case .cloud:
            return try await remoteAdvisories(
                for: results,
                rules: rules,
                includeNonReview: includeNonReview,
                engine: .cloud
            ) { try await self.cloud.explain(result: $0, rule: $1) }
        case .claudeCode:
            return try await remoteAdvisories(
                for: results,
                rules: rules,
                includeNonReview: includeNonReview,
                engine: .claudeCode
            ) { try await self.claudeCode.explain(result: $0, rule: $1) }
        case .codex:
            return try await remoteAdvisories(
                for: results,
                rules: rules,
                includeNonReview: includeNonReview,
                engine: .codex
            ) { try await self.codex.explain(result: $0, rule: $1) }
        }
    }

    /// Whether the engine assigned to `.advisory` is configured and ready.
    public func isAvailable() -> Bool {
        switch assignment(.advisory) {
        case .template, .mlx: return true
        case .cloud: return cloud.canExplainDeeper()
        case .claudeCode: return claudeCode.canExplainDeeper()
        case .codex: return codex.canExplain()
        }
    }

    private func remoteAdvisories(
        for results: [ScanResult],
        rules: [String: ScanRule],
        includeNonReview: Bool,
        engine: AIEngineID,
        explain: (ScanResult, ScanRule) async throws -> AIExplanation
    ) async throws -> [ScanResultAdvisory] {
        let eligible = AdvisoryEligibility.filter(results, includeNonReview: includeNonReview)
        guard !eligible.isEmpty else { return [] }
        guard isAvailable() else { throw AdvisoryRouterError.engineUnavailable(engine) }

        var advisories: [ScanResultAdvisory] = []
        for result in eligible {
            guard let rule = rules[result.id] else { continue }
            do {
                let explanation = try await explain(result, rule)
                advisories.append(ScanResultAdvisory(
                    resultId: result.id,
                    rationale: explanation.text,
                    suggestedSafety: result.safety,
                    source: explanation.source
                ))
            } catch {
                if let fallback = LocalAIService.yamlFallback(for: result, rules: rules) {
                    advisories.append(fallback)
                }
            }
        }
        return advisories
    }
}

/// The review tiers an advisory pass considers. Centralized so the local and
/// remote routing paths apply identical eligibility — review-tier only by
/// default, or every non-protected item when the caller opts into triage.
public enum AdvisoryEligibility {
    public static func filter(_ results: [ScanResult], includeNonReview: Bool) -> [ScanResult] {
        includeNonReview
            ? results.filter { $0.safety != .protected_ }
            : results.filter { $0.safety == .review }
    }
}

public enum AdvisoryRouterError: Error, LocalizedError, Equatable {
    /// A remote engine is assigned to advisories but isn't configured yet.
    case engineUnavailable(AIEngineID)

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable(let engine):
            switch engine {
            case .cloud:
                return "Cloud AI isn't ready. Enable it and add an API key in Settings → AI."
            case .claudeCode:
                return "Claude Code isn't ready. Enable the agent in Settings → AI → Claude Code Agent."
            case .codex:
                return "Codex isn't ready. Enable the agent in Settings → AI → Codex."
            case .template, .mlx:
                return "The local AI engine isn't ready."
            }
        }
    }
}
