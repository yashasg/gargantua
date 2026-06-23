import Foundation
import Testing
@testable import GargantuaCore

@Suite("AdvisoryRouter")
@MainActor
struct AdvisoryRouterTests {
    private func makeResult(
        id: String = "r1",
        safety: SafetyLevel = .review
    ) -> ScanResult {
        ScanResult(
            id: id,
            name: "Sample Cache",
            path: "/Users/test/Library/Caches/Sample",
            size: 100_000,
            safety: safety,
            confidence: 55,
            explanation: "Review-tier YAML explanation.",
            source: SourceAttribution(name: "Sample", bundleID: nil),
            category: "cache",
            tags: ["cache"],
            regenerates: true
        )
    }

    private func makeNeverDownloadedManager() -> ModelDownloadManager {
        let info = ModelInfo(
            id: "test-never-\(UUID().uuidString)",
            name: "Unstaged test model",
            files: [
                ModelFile(
                    name: "placeholder",
                    url: URL(string: "https://example.invalid/x")!,
                    sha256: String(repeating: "0", count: 64),
                    size: 1
                ),
            ]
        )
        return ModelDownloadManager(modelInfo: info)
    }

    @Test("A local assignment dispatches to the local service (template output)")
    func localDispatch() async throws {
        let service = LocalAIService(downloadManager: makeNeverDownloadedManager())
        let router = AdvisoryRouter(
            local: service,
            cloud: CloudAIService(),
            assignment: { _ in .template }
        )

        let result = makeResult()
        let rules = AIAdvisoryController.derivedRules(for: [result])
        let advisories = try await router.advisory(for: [result], rules: rules)

        #expect(advisories.count == 1)
        #expect(advisories.first?.source == .template)
        #expect(advisories.first?.resultId == "r1")
    }

    @Test("An unconfigured remote engine throws engineUnavailable, not silent rule fallback")
    func remoteUnavailableThrows() async throws {
        let service = LocalAIService(downloadManager: makeNeverDownloadedManager())
        let router = AdvisoryRouter(
            local: service,
            cloud: CloudAIService(),
            assignment: { _ in .cloud }
        )

        let result = makeResult()
        let rules = AIAdvisoryController.derivedRules(for: [result])

        await #expect(throws: AdvisoryRouterError.engineUnavailable(.cloud)) {
            _ = try await router.advisory(for: [result], rules: rules)
        }
    }

    @Test("No eligible items short-circuits before touching the engine")
    func noEligibleSkipsAvailabilityCheck() async throws {
        let service = LocalAIService(downloadManager: makeNeverDownloadedManager())
        // Cloud is unavailable, but a batch with nothing review-tier should
        // return [] without throwing — there's no work to route.
        let router = AdvisoryRouter(
            local: service,
            cloud: CloudAIService(),
            assignment: { _ in .cloud }
        )

        let safeOnly = [makeResult(id: "safe", safety: .safe)]
        let rules = AIAdvisoryController.derivedRules(for: safeOnly)
        let advisories = try await router.advisory(for: safeOnly, rules: rules)
        #expect(advisories.isEmpty)
    }

    @Test("Eligibility: review-only by default, all non-protected when including non-review")
    func eligibilityFiltering() {
        let results = [
            makeResult(id: "safe", safety: .safe),
            makeResult(id: "review", safety: .review),
            makeResult(id: "protected", safety: .protected_),
        ]

        let reviewOnly = AdvisoryEligibility.filter(results, includeNonReview: false)
        #expect(reviewOnly.map(\.id) == ["review"])

        let triage = AdvisoryEligibility.filter(results, includeNonReview: true)
        #expect(Set(triage.map(\.id)) == ["safe", "review"])
    }
}
