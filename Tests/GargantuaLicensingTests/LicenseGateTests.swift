import Foundation
import Testing
@testable import GargantuaLicensing

@Suite("LicenseGate")
struct LicenseGateTests {
    private func makeGate(
        client: MockPolarClient = MockPolarClient(),
        storage: any LicenseReceiptStorage = InMemoryLicenseReceiptStorage(),
        graceInterval: TimeInterval = LicensePolarConfig.validationGraceInterval,
        trialStorage: any TrialClockStorage = InMemoryTrialClockStorage(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> (LicenseGate, LicenseStore) {
        let store = LicenseStore(
            storage: storage,
            legacyFileURL: nil,
            migrationMarker: InMemoryLicenseMigrationMarker(),
            client: client,
            graceInterval: graceInterval,
            now: now,
            deviceLabel: { "Test Mac" }
        )
        let clock = TrialClock(storage: trialStorage, now: now)
        return (LicenseGate(store: store, clock: clock), store)
    }

    @Test("Failed local save maps to receiptSaveFailed, not a network error")
    func saveFailureIsNotANetworkError() async {
        let client = MockPolarClient()
        let (gate, _) = makeGate(client: client, storage: FailingLicenseReceiptStorage())

        let result = await gate.activate(key: "GARG-1")

        guard case .failure(let error) = result else {
            Issue.record("Expected failure, got \(result)")
            return
        }
        guard case .receiptSaveFailed = error else {
            Issue.record("Expected .receiptSaveFailed, got \(error)")
            return
        }
        // Slot was rolled back so a retry is safe.
        #expect(client.deactivateCount == 1)
    }

    #if GARGANTUA_LICENSING
        @Test("Fresh install enters trial mode and allows destructive actions")
        func freshInstallAllowsTrial() async {
            let (gate, _) = makeGate()

            let state = await gate.currentState()
            let decision = await gate.canExecuteDestructiveAction()

            if case .trial(let days) = state {
                #expect(days == 14)
            } else {
                Issue.record("Expected .trial state, got \(state)")
            }
            #expect(decision == .allowed)
        }

        @Test("Elapsed trial with no license blocks destructive actions")
        func expiredTrialBlocks() async {
            let start = Date(timeIntervalSince1970: 1_750_000_000)
            let storage = InMemoryTrialClockStorage(initialDate: start)
            let day30 = start.addingTimeInterval(30 * 24 * 60 * 60)
            let (gate, _) = makeGate(trialStorage: storage, now: { day30 })

            let state = await gate.currentState()
            let decision = await gate.canExecuteDestructiveAction()

            #expect(state == .expired)
            #expect(decision == .blocked(reason: .trialExpired))
        }

        @Test("Activated license overrides trial expiry")
        func activatedLicenseOverridesTrial() async throws {
            let start = Date(timeIntervalSince1970: 1_750_000_000)
            let storage = InMemoryTrialClockStorage(initialDate: start)
            let day30 = start.addingTimeInterval(30 * 24 * 60 * 60)
            let client = MockPolarClient(
                activateResult: .success(
                    PolarActivation(activationId: "act-9", status: .granted, email: "paid@user.com", name: "Paid")
                )
            )
            let (gate, store) = makeGate(client: client, trialStorage: storage, now: { day30 })
            try await store.activate(key: "GARG-PAID")

            let state = await gate.currentState()
            let decision = await gate.canExecuteDestructiveAction()

            if case .licensed(let email, _, _) = state {
                #expect(email == "paid@user.com")
            } else {
                Issue.record("Expected .licensed state, got \(state)")
            }
            #expect(decision == .allowed)
        }

        @Test("Past-grace cached license falls back to trial/expired")
        func pastGraceFallsBack() async throws {
            let start = Date(timeIntervalSince1970: 1_750_000_000)
            // Trial also expired so we land on .expired, not .trial
            let trialStorage = InMemoryTrialClockStorage(initialDate: start)
            let receiptStorage = InMemoryLicenseReceiptStorage()
            let client = MockPolarClient()
            let (_, earlyStore) = makeGate(
                client: client, storage: receiptStorage, graceInterval: 100, now: { start }
            )
            try await earlyStore.activate(key: "GARG-OLD") // lastValidated = start

            // Far past both grace window and trial
            let later = start.addingTimeInterval(60 * 24 * 60 * 60)
            let (gate, _) = makeGate(
                client: client, storage: receiptStorage, graceInterval: 100,
                trialStorage: trialStorage, now: { later }
            )

            let state = await gate.currentState()
            #expect(state == .expired)
        }
    #else
        @Test("Source build always returns .licensed and allows destructive actions")
        func sourceBuildAlwaysAllows() async {
            let (gate, _) = makeGate()

            let state = await gate.currentState()
            let decision = await gate.canExecuteDestructiveAction()

            if case .licensed(let email, _, _) = state {
                #expect(email == "source-build@local")
            } else {
                Issue.record("Expected .licensed state in source build, got \(state)")
            }
            #expect(decision == .allowed)
        }
    #endif
}
