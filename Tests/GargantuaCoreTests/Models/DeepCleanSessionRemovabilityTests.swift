import Foundation
import Testing
@testable import GargantuaCore

@Suite("DeepCleanSessionState removability")
@MainActor
struct DeepCleanSessionRemovabilityTests {
    private func result(
        id: String,
        path: String,
        safety: SafetyLevel,
        tags: [String] = []
    ) -> ScanResult {
        ScanResult(
            id: id,
            name: id,
            path: path,
            size: 1024,
            safety: safety,
            confidence: 80,
            explanation: "test",
            source: SourceAttribution(name: "Test"),
            category: "system_logs",
            tags: tags
        )
    }

    @Test("finishScan pre-selects safe removable items but never view-only ones")
    func finishScanExcludesViewOnly() {
        let session = DeepCleanSessionState()
        let safeUser = result(id: "safe", path: "/Users/x/Library/Caches/a", safety: .safe)
        // A privileged path not in the allowlist: view-only even though we force
        // safety .safe — removability is independent of the safety level.
        let viewOnly = result(
            id: "vo",
            path: "/private/var/db/diagnostics/logd.1.log",
            safety: .safe,
            tags: ["privileged"]
        )

        session.finishScan(results: [safeUser, viewOnly], duration: 0.1)

        #expect(session.selectedResultIDs == ["safe"])
        #expect(session.isSelectable("safe"))
        #expect(!session.isSelectable("vo"))
        #expect(session.viewOnlyReason("vo") != nil)
    }

    @Test("select() refuses view-only items")
    func selectRefusesViewOnly() {
        let session = DeepCleanSessionState()
        let viewOnly = result(
            id: "vo",
            path: "/private/var/db/diagnostics/x",
            safety: .review,
            tags: ["privileged"]
        )
        session.finishScan(results: [viewOnly], duration: 0)

        session.select("vo")
        #expect(session.selectedResultIDs.isEmpty)
    }

    @Test("clearing resets the removability map")
    func clearResetsRemovability() {
        let session = DeepCleanSessionState()
        session.finishScan(
            results: [result(id: "a", path: "/Users/x/a", safety: .safe)],
            duration: 0
        )
        #expect(!session.removability.isEmpty)
        session.clearResults()
        #expect(session.removability.isEmpty)
    }
}
