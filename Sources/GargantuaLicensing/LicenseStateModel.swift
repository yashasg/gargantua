import Foundation
import Observation

@MainActor
@Observable
public final class LicenseStateModel {
    public static let shared = LicenseStateModel()

    public private(set) var state: LicenseState = .none

    private let gate: LicenseGate

    public init(gate: LicenseGate = .shared) {
        self.gate = gate
    }

    public func refresh() async {
        state = await gate.currentState()
    }
}
