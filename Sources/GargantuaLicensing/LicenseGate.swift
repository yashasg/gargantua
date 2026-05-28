import Foundation

public actor LicenseGate {
    public static let shared = LicenseGate.makeDefault()

    private let store: LicenseStore
    private let clock: TrialClock

    public init(store: LicenseStore, clock: TrialClock) {
        self.store = store
        self.clock = clock
    }

    public static func makeDefault() -> LicenseGate {
        LicenseGate(
            store: LicenseStore(),
            clock: TrialClock()
        )
    }

    public func canExecuteDestructiveAction() async -> GateDecision {
        switch await currentState() {
        case .licensed:
            return .allowed
        case .trial(let days) where days > 0:
            return .allowed
        case .trial, .expired:
            return .blocked(reason: .trialExpired)
        case .none:
            return .blocked(reason: .noLicense)
        }
    }

    public func currentState() async -> LicenseState {
        #if GARGANTUA_LICENSING
            if let receipt = store.loadValidReceipt() {
                return .licensed(
                    email: receipt.email ?? "—",
                    name: receipt.name ?? "—",
                    activatedAt: receipt.activatedDate ?? Date()
                )
            }
            let days = clock.daysRemaining()
            if days > 0 {
                return .trial(daysRemaining: days)
            }
            return .expired
        #else
            return .licensed(
                email: "source-build@local",
                name: "Source Build",
                activatedAt: .distantPast
            )
        #endif
    }
}

extension LicenseReceipt {
    /// Best-effort parse of the `Timestamp` field — FastSpring's AquaticPrime
    /// template emits this in RFC822 format. Falls through to nil when the
    /// field is missing or unparseable; callers should fall back to `Date()`.
    public var activatedDate: Date? {
        guard let stamp = timestampString else { return nil }
        let rfc822 = DateFormatter()
        rfc822.locale = Locale(identifier: "en_US_POSIX")
        rfc822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        if let date = rfc822.date(from: stamp) { return date }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: stamp)
    }
}
