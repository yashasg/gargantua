import Foundation

/// Resolves where a running process came from by walking a confidence ladder
/// against the `LaunchdItemIndex`:
///
///   exact   — parent PID is launchd (1) AND a launchd item's executable
///             path matches the process's `proc_pidpath`.
///   path    — a launchd item's executable path matches the process's path,
///             regardless of who the process is parented under (helpers
///             relaunched out-of-band, fork trees, etc.).
///   heuristic — only the process basename / command name resembles a
///               launchd label; no path link.
///   unknown — nothing matches.
///
/// Pure function: takes pre-enumerated launchd items and returns the source
/// + confidence. No I/O, no globals; tests drive it from constants.
public struct ProcessLaunchSourceMatcher: Sendable {

    public init() {}

    /// Back-compat entry point: builds a one-shot index and matches against it.
    /// Callers that match many processes against the same launchd set should
    /// build a `LaunchdMatchIndex` once and use `match(…, index:)` — this
    /// overload rebuilds the index on every call.
    public func match(
        executablePath: String?,
        command: String,
        parentPID: Int32,
        launchdItems: [LaunchdItem]
    ) -> (source: ProcessLaunchSource, confidence: LaunchSourceConfidence) {
        match(
            executablePath: executablePath,
            command: command,
            parentPID: parentPID,
            index: LaunchdMatchIndex(launchdItems)
        )
    }

    /// Match against a pre-built `LaunchdMatchIndex`. The whole confidence
    /// ladder is O(1) per process: two dictionary lookups instead of a linear
    /// scan that re-lowercased every label for every process.
    public func match(
        executablePath: String?,
        command: String,
        parentPID: Int32,
        index: LaunchdMatchIndex
    ) -> (source: ProcessLaunchSource, confidence: LaunchSourceConfidence) {
        // 1. Path match — strongest signal, keyed on the absolute `Program` /
        //    `programArguments[0]` path.
        if let executablePath, !executablePath.isEmpty,
           let entry = index.pathEntry(for: executablePath) {
            let isLaunchdParent = (parentPID == 1)
            return (
                .launchd(domain: entry.domain, label: entry.label, plistPath: entry.plistPath),
                isLaunchdParent ? .exact : .path
            )
        }

        // 2. Heuristic match — process command name equals a launchd label or
        //    its trailing reverse-DNS component. Only fires when path missed.
        let commandLower = command.lowercased()
        if !commandLower.isEmpty, let entry = index.labelEntry(for: commandLower) {
            return (
                .launchd(domain: entry.domain, label: entry.label, plistPath: entry.plistPath),
                .heuristic
            )
        }

        // 3. Parent-based fallback. Parented under launchd (PID 1) but no
        //    plist matched: treat as user session helper. Otherwise it's a
        //    child of another process the inventory will surface separately.
        if parentPID == 1 {
            return (.userSession, .unknown)
        }
        if parentPID > 0 {
            return (.childProcess(parentPID: parentPID), .unknown)
        }
        return (.unknown, .unknown)
    }
}

/// Pre-computed lookup tables over a launchd item set, so resolving each of the
/// ~hundreds of running processes is O(1) rather than a fresh linear scan that
/// re-lowercased every label for every process (the old O(P×L) cost). Build it
/// once per scan and hand it to `ProcessLaunchSourceMatcher.match(…, index:)`.
public struct LaunchdMatchIndex: Sendable {
    /// The three fields `match` returns, resolved at build time so the lookups
    /// never touch the (optional) `plist` again.
    fileprivate struct Entry: Sendable {
        let domain: LaunchdDomain
        let label: String
        let plistPath: String
    }

    /// Absolute `Program` / `programArguments[0]` path → first declaring item.
    private let byExecutablePath: [String: Entry]
    /// Lowercased full label AND trailing reverse-DNS component → first
    /// declaring item. Both keys share one table so a lookup preserves the old
    /// "first item in declaration order matching label OR trailing" semantics.
    private let byLabel: [String: Entry]

    public init(_ items: [LaunchdItem]) {
        var byExecutablePath: [String: Entry] = [:]
        var byLabel: [String: Entry] = [:]
        for item in items {
            guard let plist = item.plist else { continue }
            let entry = Entry(domain: item.domain, label: plist.label, plistPath: item.plistPath)

            // Only absolute paths are matchable; a relative argv[0] would
            // false-positive across every job whose binary shares a name.
            if let program = plist.program, !program.isEmpty, byExecutablePath[program] == nil {
                byExecutablePath[program] = entry
            }
            if let argv0 = plist.programArguments.first, argv0.hasPrefix("/"), byExecutablePath[argv0] == nil {
                byExecutablePath[argv0] = entry
            }

            // First declaration wins for either label key, matching the old
            // linear scan that returned the first item satisfying the predicate.
            let labelLower = plist.label.lowercased()
            if !labelLower.isEmpty, byLabel[labelLower] == nil {
                byLabel[labelLower] = entry
            }
            if let lastDot = labelLower.lastIndex(of: ".") {
                let trailing = String(labelLower[labelLower.index(after: lastDot)...])
                if !trailing.isEmpty, byLabel[trailing] == nil {
                    byLabel[trailing] = entry
                }
            }
        }
        self.byExecutablePath = byExecutablePath
        self.byLabel = byLabel
    }

    fileprivate func pathEntry(for executablePath: String) -> Entry? {
        byExecutablePath[executablePath]
    }

    /// `commandLower` must already be lowercased by the caller.
    fileprivate func labelEntry(for commandLower: String) -> Entry? {
        byLabel[commandLower]
    }
}
