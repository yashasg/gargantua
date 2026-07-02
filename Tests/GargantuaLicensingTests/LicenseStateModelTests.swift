import Foundation
import Testing
@testable import GargantuaLicensing

@Suite("LicenseStateModel")
struct LicenseStateModelTests {
    @Test("Revalidation repeats for as long as the model lives")
    @MainActor
    func periodicRevalidationKeepsRunning() async throws {
        let client = MockPolarClient()
        let store = LicenseStore(
            storage: InMemoryLicenseReceiptStorage(),
            legacyFileURL: nil,
            migrationMarker: InMemoryLicenseMigrationMarker(),
            client: client,
            deviceLabel: { "Test Mac" }
        )
        try await store.activate(key: "GARG-1")
        let gate = LicenseGate(store: store, clock: TrialClock(storage: InMemoryTrialClockStorage()))

        let model = LicenseStateModel(gate: gate, revalidationInterval: .milliseconds(20))

        // The init-time revalidate plus at least two periodic rounds. Poll
        // with a generous ceiling so slow CI can't flake this.
        for _ in 0 ..< 200 where client.validateCount < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(client.validateCount >= 3)
        _ = model // keep the model (and its revalidation task) alive while polling
    }
}
