import Testing
@testable import GargantuaCore

@Suite("BackgroundItemsView pre-selection")
struct BackgroundItemsPreSelectionTests {
    @Test("a hit expands regardless of rescan history")
    func hitExpands() {
        #expect(BackgroundItemsView.preSelectionStep(
            matchFound: true,
            alreadyRescannedForPath: false
        ) == .expand)
        #expect(BackgroundItemsView.preSelectionStep(
            matchFound: true,
            alreadyRescannedForPath: true
        ) == .expand)
    }

    @Test("a miss rescans once — the cached scan may predate the item — then reports missing")
    func missRescansOnceThenReports() {
        #expect(BackgroundItemsView.preSelectionStep(
            matchFound: false,
            alreadyRescannedForPath: false
        ) == .rescanFirst)
        #expect(BackgroundItemsView.preSelectionStep(
            matchFound: false,
            alreadyRescannedForPath: true
        ) == .reportMissing)
    }
}
