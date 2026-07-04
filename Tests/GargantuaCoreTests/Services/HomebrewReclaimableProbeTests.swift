import Foundation
import Testing
@testable import GargantuaCore

private func cleanupItem(_ bytes: Int64?) -> DeveloperToolPreviewItem {
    DeveloperToolPreviewItem(
        id: "cleanup-\(bytes.map(String.init) ?? "nil")",
        tool: .homebrew,
        title: "Would remove cache",
        reclaimableBytes: bytes,
        commandPreview: ["brew", "cleanup", "-n"]
    )
}

private func orphan(_ bytes: Int64?) -> DeveloperToolPreviewItem {
    DeveloperToolPreviewItem(
        id: "orphan-\(bytes.map(String.init) ?? "nil")",
        tool: .homebrew,
        title: "Orphan formula",
        reclaimableBytes: bytes,
        commandPreview: ["brew", "autoremove"]
    )
}

private func preview(
    cleanup: [Int64?],
    orphans: [Int64?]? = nil
) -> DeveloperToolPreview {
    DeveloperToolPreview(
        tool: .homebrew,
        commandPreview: ["brew", "cleanup", "-n"],
        items: cleanup.map(cleanupItem),
        rawOutput: "",
        homebrewAutoremove: orphans.map { HomebrewAutoremovePreview(formulae: $0.map(orphan)) }
    )
}

@Suite("HomebrewReclaimableProbe")
struct HomebrewReclaimableProbeTests {
    @Test("total sums cleanup (cache + old versions) and orphan Cellar sizes")
    func sumsCleanupAndOrphans() {
        let p = preview(cleanup: [1_000, 2_000], orphans: [500, 1_500])
        #expect(HomebrewReclaimableProbe.totalBytes(for: p) == 5_000)
    }

    @Test("no autoremove data counts cleanup only, not a crash")
    func cleanupOnlyWhenNoAutoremove() {
        let p = preview(cleanup: [4_096], orphans: nil)
        #expect(HomebrewReclaimableProbe.totalBytes(for: p) == 4_096)
    }

    @Test("empty orphan list contributes zero")
    func emptyOrphansAddNothing() {
        let p = preview(cleanup: [3_000], orphans: [])
        #expect(HomebrewReclaimableProbe.totalBytes(for: p) == 3_000)
    }

    @Test("nothing reclaimable totals zero")
    func nothingReclaimable() {
        let p = preview(cleanup: [], orphans: [])
        #expect(HomebrewReclaimableProbe.totalBytes(for: p) == 0)
    }

    @Test("overflow saturates at Int64.max instead of trapping")
    func saturatesOnOverflow() {
        let p = preview(cleanup: [.max], orphans: [1])
        #expect(HomebrewReclaimableProbe.totalBytes(for: p) == .max)
    }
}
