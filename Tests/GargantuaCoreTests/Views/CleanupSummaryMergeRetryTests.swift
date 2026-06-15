import Testing
@testable import GargantuaCore

@Suite("CleanupSummaryView.mergeRetry")
struct CleanupSummaryMergeRetryTests {

    private func item(_ id: String) -> ScanResult {
        ScanResult(
            id: id,
            name: id,
            path: "/tmp/\(id)",
            size: 100,
            safety: .safe,
            confidence: 90,
            explanation: "x",
            source: SourceAttribution(name: "test"),
            category: "cache"
        )
    }

    private func failed(_ id: String) -> CleanupItemResult {
        CleanupItemResult(item: item(id), succeeded: false, error: "Operation not permitted")
    }

    private func ok(_ id: String) -> CleanupItemResult {
        CleanupItemResult(item: item(id), succeeded: true)
    }

    @Test("A short (cancelled) retry never drops items")
    func shortRetryKeepsAll() {
        let current = [ok("a"), failed("b"), failed("c"), failed("d")]
        // Retry recovered b, then was cancelled before c/d — engine returns only b.
        let merged = CleanupSummaryView.mergeRetry(into: current, retry: [ok("b")])

        #expect(merged.count == 4) // nothing vanished
        #expect(merged.first { $0.item.id == "a" }?.succeeded == true)
        #expect(merged.first { $0.item.id == "b" }?.succeeded == true) // recovered
        #expect(merged.first { $0.item.id == "c" }?.succeeded == false) // untouched
        #expect(merged.first { $0.item.id == "d" }?.succeeded == false)
    }

    @Test("A full retry updates each re-run item and preserves order")
    func fullRetryUpdatesInPlace() {
        let current = [failed("x"), failed("y")]
        let merged = CleanupSummaryView.mergeRetry(into: current, retry: [ok("x"), failed("y")])

        #expect(merged.map(\.item.id) == ["x", "y"])
        #expect(merged[0].succeeded == true)
        #expect(merged[1].succeeded == false)
    }

    @Test("An empty retry leaves the result unchanged")
    func emptyRetryNoop() {
        let current = [ok("a"), failed("b")]
        let merged = CleanupSummaryView.mergeRetry(into: current, retry: [])
        #expect(merged.count == 2)
        #expect(merged.first { $0.item.id == "b" }?.succeeded == false)
    }
}
