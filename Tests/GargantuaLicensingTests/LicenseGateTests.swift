import Foundation
import Testing
@testable import GargantuaLicensing

@Suite("LicenseGate")
struct LicenseGateTests {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gargantua-gate-tests", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).gargantualicense", isDirectory: false)
    }

    private func makeGate(
        receiptURL: URL? = nil,
        storage: any TrialClockStorage = InMemoryTrialClockStorage(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> LicenseGate {
        let store = LicenseStore(
            fileURL: receiptURL ?? tempFileURL(),
            publicKey: TestKeys.developmentPublicKey
        )
        let clock = TrialClock(storage: storage, now: now)
        return LicenseGate(store: store, clock: clock)
    }

    #if GARGANTUA_LICENSING
        @Test("Fresh install enters trial mode and allows destructive actions")
        func freshInstallAllowsTrial() async {
            let gate = makeGate()

            let state = await gate.currentState()
            let decision = await gate.canExecuteDestructiveAction()

            if case .trial(let days) = state {
                #expect(days == 14)
            } else {
                Issue.record("Expected .trial state, got \(state)")
            }
            #expect(decision == .allowed)
        }

        @Test("Trial that has elapsed blocks destructive actions")
        func expiredTrialBlocks() async {
            let start = Date(timeIntervalSince1970: 1_750_000_000)
            let storage = InMemoryTrialClockStorage(initialDate: start)
            let day30 = start.addingTimeInterval(30 * 24 * 60 * 60)
            let gate = makeGate(storage: storage, now: { day30 })

            let state = await gate.currentState()
            let decision = await gate.canExecuteDestructiveAction()

            #expect(state == .expired)
            #expect(decision == .blocked(reason: .trialExpired))
        }

        @Test("Saved valid license overrides trial expiry")
        func validLicenseOverridesTrial() async throws {
            let url = tempFileURL()
            defer { try? FileManager.default.removeItem(at: url) }
            let start = Date(timeIntervalSince1970: 1_750_000_000)
            let storage = InMemoryTrialClockStorage(initialDate: start)
            let day30 = start.addingTimeInterval(30 * 24 * 60 * 60)

            let store = LicenseStore(
                fileURL: url,
                publicKey: TestKeys.developmentPublicKey
            )
            let plistData = try TestKeys.signedLicensePlist(fields: [
                "Product": "Gargantua",
                "Name": "Paid User",
                "Email": "paid@user.com",
                "Order": "ORDER-9",
                "Timestamp": "Thu, 28 May 2026 12:00:00 +0000",
            ])
            try store.save(plistData: plistData)

            let clock = TrialClock(storage: storage, now: { day30 })
            let gate = LicenseGate(store: store, clock: clock)

            let state = await gate.currentState()
            let decision = await gate.canExecuteDestructiveAction()

            if case .licensed(let email, _, _) = state {
                #expect(email == "paid@user.com")
            } else {
                Issue.record("Expected .licensed state, got \(state)")
            }
            #expect(decision == .allowed)
        }
    #else
        @Test("Source build always returns .licensed and allows destructive actions")
        func sourceBuildAlwaysAllows() async {
            let gate = makeGate()

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
