import AppKit
import GargantuaLicensing
import SwiftUI

/// Single implementation of the destructive-action license gate shared by every
/// GUI surface that deletes files — Deep Clean, AI Models, Duplicate Finder,
/// File Health, Dev Artifacts, and the summary "retry failed" path.
///
/// A surface calls ``blockReason()`` immediately before it touches
/// `CleanupEngine`. A non-nil result means the trial has lapsed (or there was
/// never a license), so the surface stashes it in its own `blockedReason` state
/// and bails before anything is deleted; ``SwiftUI/View/destructiveActionGate(reason:)``
/// renders the Unlock sheet from that state.
///
/// Both halves live here on purpose: a new destructive surface reuses the exact
/// same decision *and* the exact same sheet wiring instead of hand-rolling — or
/// forgetting — its own gate.
public enum DestructiveActionGate {
    /// Returns `nil` when the destructive action may proceed, or the
    /// `BlockReason` to raise the Unlock sheet when it may not.
    ///
    /// - Parameter decide: The gate-decision source. Defaults to the shared
    ///   `LicenseGate`; tests inject a fixed decision so the blocked branch is
    ///   reachable without the `GARGANTUA_LICENSING` trial machinery (a source
    ///   build always resolves to `.allowed`).
    public static func blockReason(
        decide: () async -> GateDecision = { await LicenseGate.shared.canExecuteDestructiveAction() }
    ) async -> BlockReason? {
        if case .blocked(let reason) = await decide() {
            return reason
        }
        return nil
    }
}

public extension View {
    /// Presents the shared Unlock sheet whenever `reason` is non-nil. Attach to
    /// any destructive surface and drive `reason` from
    /// ``DestructiveActionGate/blockReason(decide:)``.
    func destructiveActionGate(reason: Binding<BlockReason?>) -> some View {
        modifier(DestructiveActionGateSheet(reason: reason))
    }
}

private struct DestructiveActionGateSheet: ViewModifier {
    @Binding var reason: BlockReason?

    func body(content: Content) -> some View {
        content.sheet(item: $reason) { blockReason in
            UnlockGargantuaSheet(
                reason: blockReason,
                onDismiss: { reason = nil },
                onBuy: {
                    NSWorkspace.shared.open(LicensePolarConfig.checkoutURL)
                    reason = nil
                },
                onActivate: { key in
                    switch await LicenseStateModel.shared.activate(key: key) {
                    case .success:
                        return .ok
                    case .failure(let error):
                        return .error(LicenseErrorCopy.message(for: error))
                    }
                }
            )
        }
    }
}
