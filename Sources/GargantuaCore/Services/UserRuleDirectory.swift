import Foundation

/// Resolves the user-writable rules directory and its per-family subfolders.
///
/// User rules live under `~/Library/Application Support/Gargantua/rules/`, which
/// sits *outside* the app bundle. Sparkle replaces the bundle wholesale on
/// update, so anything authored here survives upgrades — unlike the bundled,
/// signed snapshot under `GargantuaCore.bundle/Resources`.
///
/// User rules are deliberately *less* trusted than bundled rules: everything
/// loaded from these folders is run through `UserRuleSanitizer`, which floors
/// every classification to `review` (a user rule can surface a candidate but
/// can never declare it one-click `safe`) and strips profile-scoped safety
/// overrides. See `UserRuleSanitizer` for the full clamp.
public enum UserRuleDirectory {
    /// Family of user rules, mapped to its subfolder name.
    public enum Family: String, CaseIterable, Sendable {
        case cleanup
        case uninstall
        case command
    }

    /// Root of the user rules tree, e.g.
    /// `~/Library/Application Support/Gargantua/rules`.
    public static func root(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("Gargantua", isDirectory: true)
            .appendingPathComponent("rules", isDirectory: true)
    }

    /// Subfolder for a given rule family. Returns the URL whether or not it
    /// exists on disk; callers that need it to exist should call `ensureScaffold`.
    public static func directory(for family: Family, fileManager: FileManager = .default) -> URL {
        root(fileManager: fileManager).appendingPathComponent(family.rawValue, isDirectory: true)
    }

    /// Create the rules tree (root + all family subfolders) and drop a README
    /// explaining the clamp, if one isn't already present. Idempotent.
    @discardableResult
    public static func ensureScaffold(fileManager: FileManager = .default) -> URL {
        let root = root(fileManager: fileManager)
        for family in Family.allCases {
            try? fileManager.createDirectory(
                at: directory(for: family, fileManager: fileManager),
                withIntermediateDirectories: true
            )
        }

        let readme = root.appendingPathComponent("README.txt")
        if !fileManager.fileExists(atPath: readme.path) {
            try? readmeBody.write(to: readme, atomically: true, encoding: .utf8)
        }
        return root
    }

    private static let readmeBody = """
    Gargantua — user rules
    ======================

    Drop your own rule files (*.yaml / *.yml) into these folders:

      cleanup/    Deep Clean rules    (path globs to find and classify)
      uninstall/  Smart Uninstaller   (leftover-file templates)
      command/    Advanced Commands   (tool-native cleanup commands)

    They load alongside the bundled, reviewed rules every scan, and they
    survive app updates (the bundled snapshot is replaced on update; this
    folder is not).

    Trust clamp — user rules are deliberately less privileged than bundled
    rules. Whatever you write here is treated conservatively:

      * Safety is floored to "review". A user rule can surface an item, but
        it can never classify one as one-click "safe". Anything you mark
        "safe" loads as "review".
      * Profile-scoped safety overrides are dropped.
      * Command rules always run as "review" and are rejected if they touch
        a protected root.
      * A user rule whose id collides with a bundled rule is ignored — the
        bundled rule wins.

    Use the same YAML shape as the bundled rules. See the public schema and
    examples at https://github.com/inceptyon-labs/gargantua-rules
    """
}
