import Foundation
import Testing
@testable import GargantuaCore

@Suite("Privileged helper version reload decision")
struct PrivilegedHelperVersionReloadTests {
    @Test("Current version does not trigger a reload")
    func currentVersionNoReload() {
        let current = PrivilegedHelperConfiguration.helperVersion
        #expect(XPCPrivilegedUninstallHelper.shouldReloadHelper(running: current) == false)
    }

    @Test("Older version triggers a reload")
    func olderVersionReloads() {
        #expect(XPCPrivilegedUninstallHelper.shouldReloadHelper(running: 1) == true)
    }

    @Test("Unreachable / too-old-to-answer helper (nil) triggers a reload")
    func nilVersionReloads() {
        // A helper predating the version ping never replies; treat the resulting
        // nil as stale and reload rather than trust an unconfirmed daemon.
        #expect(XPCPrivilegedUninstallHelper.shouldReloadHelper(running: nil) == true)
    }
}
