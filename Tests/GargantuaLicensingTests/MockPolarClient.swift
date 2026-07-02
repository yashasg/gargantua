import Foundation
@testable import GargantuaLicensing

/// In-memory stand-in for `PolarLicenseValidating`. Tests set the canned
/// results and assert on what was called.
final class MockPolarClient: PolarLicenseValidating, @unchecked Sendable {
    var activateResult: Result<PolarActivation, PolarLicenseError>
    var validateResult: Result<PolarValidation, PolarLicenseError>
    var deactivateError: PolarLicenseError?

    // Counters are read from other executors while the client mutates them
    // (e.g. the periodic-revalidation test polls from @MainActor). Guard them
    // so TSan stays quiet.
    private let lock = NSLock()
    private var _activateCount = 0
    private var _validateCount = 0
    private var _deactivateCount = 0
    private var _lastValidatedActivationId: String?

    var activateCount: Int { lock.withLock { _activateCount } }
    var validateCount: Int { lock.withLock { _validateCount } }
    var deactivateCount: Int { lock.withLock { _deactivateCount } }
    var lastValidatedActivationId: String? { lock.withLock { _lastValidatedActivationId } }

    init(
        activateResult: Result<PolarActivation, PolarLicenseError> = .success(
            PolarActivation(activationId: "act-1", status: .granted, email: "buyer@example.com", name: "Buyer")
        ),
        validateResult: Result<PolarValidation, PolarLicenseError> = .success(
            PolarValidation(status: .granted, email: "buyer@example.com", name: "Buyer")
        ),
        deactivateError: PolarLicenseError? = nil
    ) {
        self.activateResult = activateResult
        self.validateResult = validateResult
        self.deactivateError = deactivateError
    }

    func activate(key: String, label: String, meta: [String: String]) async throws -> PolarActivation {
        lock.withLock { _activateCount += 1 }
        return try activateResult.get()
    }

    func validate(key: String, activationId: String?) async throws -> PolarValidation {
        lock.withLock {
            _validateCount += 1
            _lastValidatedActivationId = activationId
        }
        return try validateResult.get()
    }

    func deactivate(key: String, activationId: String) async throws {
        lock.withLock { _deactivateCount += 1 }
        if let deactivateError {
            throw deactivateError
        }
    }
}

/// Mutable, Sendable clock holder for advancing time mid-test without tripping
/// Swift 6 captured-var-in-concurrent-code diagnostics.
final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date {
        get { lock.lock(); defer { lock.unlock() }; return date }
        set { lock.lock(); defer { lock.unlock() }; date = newValue }
    }
}
