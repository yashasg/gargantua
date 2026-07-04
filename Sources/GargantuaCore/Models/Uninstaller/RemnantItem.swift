import Foundation

/// A single remnant discovered during uninstall planning.
///
/// Analogous to `ScanResult`, but keyed to an owning `AppInfo` and
/// typed `RemnantCategory`. The `safety` field is mutable so that the
/// Trust Layer can reclassify it during plan review (for example, when
/// the app is still running or when the remnant is shared with another
/// installed app).
public struct RemnantItem: Codable, Sendable, Identifiable {
    /// Stable identifier for this remnant (e.g., `slack_webdata_001`).
    public let id: String

    /// The owning app's bundle identifier, for round-trip indexing
    /// against a plan's `AppInfo`.
    public let appBundleID: String

    /// Remnant category this item belongs to.
    public let category: RemnantCategory

    /// Absolute file path.
    public let path: String

    /// Size in bytes.
    public let size: Int64

    /// Trust Layer safety classification. Mutable — see type docs.
    public var safety: SafetyLevel

    /// Confidence percentage (0–100) in the safety classification.
    public let confidence: Int

    /// One-line explanation surfaced in the Trust Layer.
    public let explanation: String

    /// Attribution for the process that created this file.
    public let source: SourceAttribution

    /// ID of the `RemnantRule` that matched this path.
    public let ruleID: String

    /// Filesystem last-accessed timestamp, when available.
    public let lastAccessed: Date?

    /// Whether the remnant would be regenerated on reinstall.
    public let regenerates: Bool

    /// Free-form tags copied from the matching rule plus any the scanner adds.
    public let tags: [String]

    /// Where `path`'s parent directory chain resolved at *discovery*
    /// (uninstall-scan) time, recorded by `RemnantScanner.plan` so the
    /// pre-delete `SymlinkSwapGuard` can tell a symlink ancestor that
    /// already existed when the remnant was found (e.g. a relocated
    /// `~/Library/Caches` → `/Volumes/Ext/Caches`) from one swapped in
    /// after the scan. Threaded into `toScanResult()`. `nil` until
    /// recorded; the guard then rejects any symlink ancestor fail-safe.
    public var scanTimeResolvedParent: String?

    public init(
        id: String,
        appBundleID: String,
        category: RemnantCategory,
        path: String,
        size: Int64,
        safety: SafetyLevel,
        confidence: Int,
        explanation: String,
        source: SourceAttribution,
        ruleID: String,
        lastAccessed: Date? = nil,
        regenerates: Bool = false,
        tags: [String] = [],
        scanTimeResolvedParent: String? = nil
    ) {
        self.id = id
        self.appBundleID = appBundleID
        self.category = category
        self.path = path
        self.size = size
        self.safety = safety
        self.confidence = confidence
        self.explanation = explanation
        self.source = source
        self.ruleID = ruleID
        self.lastAccessed = lastAccessed
        self.regenerates = regenerates
        self.tags = tags
        self.scanTimeResolvedParent = scanTimeResolvedParent
    }

    /// Returns a copy with the parent-chain resolution recorded, for the
    /// pre-delete symlink-swap guard. Must be called while the filesystem
    /// still reflects scan time — i.e. by `RemnantScanner.plan` as remnants
    /// are gathered, not at uninstall time. Non-absolute paths and
    /// already-recorded items pass through unchanged.
    public func recordingScanTimeAncestry() -> RemnantItem {
        guard scanTimeResolvedParent == nil, path.hasPrefix("/") else { return self }
        var copy = self
        copy.scanTimeResolvedParent = URL(fileURLWithPath: path)
            .standardizedFileURL
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .path
        return copy
    }
}
