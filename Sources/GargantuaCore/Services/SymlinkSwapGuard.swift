import Foundation

/// Re-validates, immediately before a non-privileged deletion, that the path a
/// scan recorded has not had a symlink swapped into its parent chain between
/// scan (the check) and clean (the use) — the classic TOCTOU window.
///
/// `FileManager.removeItem` and Finder both follow symlinked *parent*
/// components, so an attacker able to write to a scanned directory could, in the
/// race window, redirect a delete onto a file the user never selected. The
/// root-privileged helper already rejects symlinked paths
/// (`GargantuaPrivilegedHelper/main.swift`); this gives the in-process,
/// user-owned delete path the same guarantee.
///
/// A symlink at the *leaf* is not redirected here: `removeItem` on a symlink
/// unlinks the link itself rather than its target, so legitimate symlink items
/// (e.g. broken-symlink cleanup) still delete correctly. Only an ancestor
/// redirection — the dangerous case — is rejected.
///
/// macOS firmlinks (the data/system volume split surfaced as `/private/var` vs
/// `/var`, etc.) are not symlinks; `PrivilegedRemovabilityPolicy.canonical`
/// normalizes those so they never trip the check.
public enum SymlinkSwapGuard {
    /// Returns `true` when `url`'s parent chain still resolves to the same
    /// place it did at scan time — no symlink redirection has appeared above
    /// the leaf since the item was recorded.
    ///
    /// When a `scanTimeResolvedParent` recording is present it is
    /// authoritative: the parent must still resolve to exactly where it did
    /// at scan time. That rejects a symlink swapped *in* (the resolved parent
    /// moves to the attacker's target) *and* a symlink swapped *out* —
    /// replaced by a real directory at the same path — which a no-symlink
    /// fast path alone would wave through even though the item now points at
    /// different bytes. A legitimate pre-existing link such as a symlinked
    /// scan root (`~/dev` → `/Volumes/Ext/dev`) resolves unchanged and
    /// passes.
    ///
    /// Without a recording (`nil` — e.g. execution-time preview targets), the
    /// classic guarantee applies: pass only when the parent chain has no
    /// symlink at all, rejecting any symlink ancestor fail-safe.
    public static func isUnchanged(_ url: URL, scanTimeResolvedParent: String?) -> Bool {
        let parent = url.standardizedFileURL.deletingLastPathComponent()
        let resolved = PrivilegedRemovabilityPolicy.canonical(parent.resolvingSymlinksInPath().path)

        if let scanTimeResolvedParent {
            let recorded = PrivilegedRemovabilityPolicy.canonical(
                URL(fileURLWithPath: scanTimeResolvedParent).standardizedFileURL.path
            )
            return resolved == recorded
        }

        let standardized = PrivilegedRemovabilityPolicy.canonical(parent.path)
        return standardized == resolved
    }
}
