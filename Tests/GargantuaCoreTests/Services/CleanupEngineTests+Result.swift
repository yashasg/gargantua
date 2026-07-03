import Foundation
import Testing
@testable import GargantuaCore

extension CleanupResultTests {
    @Test("totalFreed sums only succeeded items")
    func totalFreedSumsSucceeded() {
        let result = CleanupResult(itemResults: [
            CleanupItemResult(item: makeItem(id: "a", size: 500), succeeded: true),
            CleanupItemResult(item: makeItem(id: "b", size: 300), succeeded: true),
            CleanupItemResult(item: makeItem(id: "c", size: 200), succeeded: false, error: "Permission denied"),
        ])

        #expect(result.totalFreed == 800)
        #expect(result.cleanupMethod == .trash)
        #expect(result.succeededItems.count == 2)
        #expect(result.failedItems.count == 1)
        #expect(!result.allSucceeded)
    }

    @Test("allSucceeded is true when no failures")
    func allSucceededWhenNoFailures() {
        let result = CleanupResult(itemResults: [
            CleanupItemResult(item: makeItem(id: "a", size: 100), succeeded: true),
            CleanupItemResult(item: makeItem(id: "b", size: 200), succeeded: true),
        ])

        #expect(result.allSucceeded)
        #expect(result.totalFreed == 300)
    }

    @Test("empty result has zero freed and allSucceeded")
    func emptyResult() {
        let result = CleanupResult(itemResults: [])

        #expect(result.totalFreed == 0)
        #expect(result.allSucceeded)
        #expect(result.succeededItems.isEmpty)
        #expect(result.failedItems.isEmpty)
    }

    @Test("all failed returns zero freed")
    func allFailed() {
        let result = CleanupResult(itemResults: [
            CleanupItemResult(item: makeItem(id: "a", size: 500), succeeded: false, error: "E1"),
            CleanupItemResult(item: makeItem(id: "b", size: 300), succeeded: false, error: "E2"),
        ])

        #expect(result.totalFreed == 0)
        #expect(!result.allSucceeded)
        #expect(result.failedItems.count == 2)
    }

    @Test("CleanupItemResult stores trash URL on success")
    func itemResultTrashURL() {
        let url = URL(fileURLWithPath: "/Users/test/.Trash/file.txt")
        let itemResult = CleanupItemResult(
            item: makeItem(),
            succeeded: true,
            trashURL: url
        )

        #expect(itemResult.trashURL == url)
        #expect(itemResult.error == nil)
    }

    @Test("CleanupItemResult stores error on failure")
    func itemResultError() {
        let itemResult = CleanupItemResult(
            item: makeItem(),
            succeeded: false,
            error: "Permission denied"
        )

        #expect(itemResult.trashURL == nil)
        #expect(itemResult.error == "Permission denied")
    }

    @Test("already-gone success credits zero bytes, not the scan-time size")
    func alreadyGoneCreditsZeroBytes() {
        // An item that vanished between scan and clean is reported as succeeded
        // (the user's intent is met) but reclaimed nothing — it must not inflate
        // the freed total by its stale scan-time size.
        let result = CleanupResult(itemResults: [
            CleanupItemResult(item: makeItem(id: "a", size: 500), succeeded: true),
            CleanupItemResult(item: makeItem(id: "gone", size: 900), succeeded: true, bytesFreed: 0),
        ])

        #expect(result.totalFreed == 500)
        #expect(result.succeededItems.count == 2)
    }

    @Test("overlapping selections of the same/nested path are counted once")
    func overlappingSelectionsDeduped() {
        // Whole-repo removal + stale-revision prune of the same repo dir, plus a
        // parent dir selected alongside a child: each freed byte counts once.
        let repo = "/Users/test/.cache/huggingface/models--org--model"
        let result = CleanupResult(itemResults: [
            CleanupItemResult(item: makeItem(id: "repo", path: repo, size: 1000), succeeded: true),
            CleanupItemResult(item: makeItem(id: "revs", path: repo, size: 400), succeeded: true),
            CleanupItemResult(item: makeItem(id: "child", path: repo + "/snapshots/x", size: 200), succeeded: true),
            CleanupItemResult(item: makeItem(id: "other", path: "/Users/test/.cache/other", size: 300), succeeded: true),
        ])

        // repo (1000, the larger of the two same-path estimates) + other (300);
        // the 400 same-path prune and the 200 nested child are absorbed.
        #expect(result.totalFreed == 1300)
    }
}
