import Foundation
import Testing
@testable import GargantuaCore

/// Drives `ClaudeCodeDeeperExplainer` through a fake `claude` CLI (a shell
/// script) so the enablement guard, prose round-trip, source stamping, and
/// error mapping are exercised end-to-end.
@Suite("ClaudeCodeDeeperExplainer")
struct ClaudeCodeDeeperExplainerTests {

    private func makeResult() -> ScanResult {
        ScanResult(
            id: "explain-me",
            name: "Chrome Cache",
            path: "/tmp/cache",
            size: 2048,
            safety: .safe,
            confidence: 95,
            explanation: "Regenerated on launch.",
            source: SourceAttribution(name: "Chrome", bundleID: "com.google.Chrome"),
            category: "browser_cache",
            tags: ["browser"],
            regenerates: true
        )
    }

    private func makeExplainer(
        enabled: Bool,
        cliBody: String = "",
        timeoutSeconds: Int = 240
    ) throws -> ClaudeCodeDeeperExplainer {
        let store = ClaudeCodeAgentConfigurationStore(defaults: OrganizerProposerTestSupport.makeDefaults())
        let cliPath = enabled
            ? try OrganizerProposerTestSupport.writeExecutableScript(cliBody).path
            : ""
        store.save(ClaudeCodeAgentConfiguration(
            isEnabled: enabled,
            cliPath: cliPath,
            selectedModel: "test-model"
        ))
        return ClaudeCodeDeeperExplainer(
            configurationStore: store,
            runner: ClaudeCodeOneShotRunner(timeoutSeconds: timeoutSeconds)
        )
    }

    @Test("Disabled agent throws before touching the CLI")
    func disabledThrows() async throws {
        let explainer = try makeExplainer(enabled: false)

        await #expect(throws: ClaudeCodeDeeperExplainError.agentNotEnabled) {
            _ = try await explainer.explain(
                result: makeResult(),
                rule: AIExplanationController.derivedRule(from: makeResult())
            )
        }
    }

    @Test("Valid CLI prose round-trips into a claudeCode-sourced explanation")
    func happyPath() async throws {
        let explainer = try makeExplainer(
            enabled: true,
            cliBody: "printf '%s' '  This is a cache. Safe to delete.  '\n"
        )
        let result = makeResult()

        let explanation = try await explainer.explain(
            result: result,
            rule: AIExplanationController.derivedRule(from: result)
        )

        #expect(explanation.source == .claudeCode)
        #expect(explanation.text == "This is a cache. Safe to delete.")
    }

    @Test("Non-zero CLI exit maps to cliFailed")
    func cliFailedMapping() async throws {
        let explainer = try makeExplainer(
            enabled: true,
            cliBody: "printf '%s' 'nope' 1>&2\nexit 3\n"
        )
        let result = makeResult()

        await #expect(throws: ClaudeCodeDeeperExplainError.cliFailed(exitCode: 3, stderr: "nope")) {
            _ = try await explainer.explain(
                result: result,
                rule: AIExplanationController.derivedRule(from: result)
            )
        }
    }

    @Test("canExplainDeeper tracks enablement")
    func canExplainDeeperTracksEnablement() throws {
        let enabled = try makeExplainer(enabled: true, cliBody: "printf '%s' 'x'\n")
        #expect(enabled.canExplainDeeper())

        let disabled = try makeExplainer(enabled: false)
        #expect(!disabled.canExplainDeeper())
    }
}
