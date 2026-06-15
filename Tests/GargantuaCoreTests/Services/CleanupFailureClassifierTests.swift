import Testing
@testable import GargantuaCore

@Suite("CleanupFailureClassifier.friendlyReason")
struct CleanupFailureReasonTests {

    @Test("Ownership/permission errors map to the helper message")
    func ownership() {
        #expect(CleanupFailureClassifier.friendlyReason(for: "Operation not permitted")
            .contains("privileged helper"))
        #expect(CleanupFailureClassifier.friendlyReason(for: "You don’t have permission to access the file.")
            .contains("privileged helper"))
    }

    @Test("Automation denial maps to the Finder Automation message")
    func automation() {
        let reason = CleanupFailureClassifier.friendlyReason(for: "Not authorized to send Apple events (-1743)")
        #expect(reason.contains("Finder Automation"))
    }

    @Test("nil, empty, and bare \"unknown error\" never leak to the user")
    func noRawFallthrough() {
        let expected = "Couldn’t be removed — macOS gave no further detail."
        #expect(CleanupFailureClassifier.friendlyReason(for: nil) == expected)
        #expect(CleanupFailureClassifier.friendlyReason(for: "") == expected)
        #expect(CleanupFailureClassifier.friendlyReason(for: "   ") == expected)
        #expect(CleanupFailureClassifier.friendlyReason(for: "unknown error") == expected)
        #expect(CleanupFailureClassifier.friendlyReason(for: "Unknown Error") == expected)
    }

    @Test("Busy/in-use errors suggest quitting the app")
    func busy() {
        #expect(CleanupFailureClassifier.friendlyReason(for: "Resource busy").contains("quit"))
        #expect(CleanupFailureClassifier.friendlyReason(for: "The file is in use.").contains("quit"))
    }

    @Test("A readable, unrecognized error passes through unchanged")
    func passthrough() {
        let raw = "The volume “Backups” could not be found."
        #expect(CleanupFailureClassifier.friendlyReason(for: raw) == raw)
    }
}
