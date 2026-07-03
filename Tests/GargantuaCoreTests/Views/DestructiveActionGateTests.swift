import GargantuaLicensing
import Testing
@testable import GargantuaCore

@MainActor
@Suite("DestructiveActionGate")
struct DestructiveActionGateTests {
    @Test("Allowed decision permits the action and raises no sheet")
    func allowedPermits() async {
        let reason = await DestructiveActionGate.blockReason(decide: { .allowed })
        #expect(reason == nil)
    }

    @Test("Expired trial blocks the action and surfaces the reason")
    func expiredTrialBlocks() async {
        let reason = await DestructiveActionGate.blockReason(decide: { .blocked(reason: .trialExpired) })
        #expect(reason == .trialExpired)
    }

    @Test("No-license block surfaces its own reason")
    func noLicenseBlocks() async {
        let reason = await DestructiveActionGate.blockReason(decide: { .blocked(reason: .noLicense) })
        #expect(reason == .noLicense)
    }
}
