import Foundation

/// Resolves the directory containing YAML cleanup rules.
///
/// Search order:
/// 1. `GARGANTUA_RULES_DIR` environment variable — DEBUG builds only. Letting an
///    env var point a release app at arbitrary YAML would bypass the Trust Layer
///    (any `safety: safe` / overrides). Release builds always use the bundled,
///    signed rule snapshot.
/// 2. `Bundle.gargantuaCoreResources.resourceURL/cleanup_rules` (SPM resource — works for
///    `swift run`, `swift test`, and a shipped `.app` that embeds the
///    `GargantuaCore_GargantuaCore.bundle`)
/// 3. `Bundle.main.resourceURL/cleanup_rules` (flat-copied .app layouts,
///    e.g. a post-build script that places rules directly in `Contents/Resources`)
public enum RuleDirectoryResolver {
    public static func resolve() -> URL? {
        let fm = FileManager.default

        #if DEBUG
            if let envPath = ProcessInfo.processInfo.environment["GARGANTUA_RULES_DIR"], !envPath.isEmpty {
                let url = URL(fileURLWithPath: envPath, isDirectory: true)
                if fm.fileExists(atPath: url.path) { return url }
            }
        #endif

        if let resourceURL = Bundle.gargantuaCoreResources.resourceURL {
            let candidate = resourceURL.appendingPathComponent("cleanup_rules", isDirectory: true)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }

        if let mainResourceURL = Bundle.main.resourceURL {
            let candidate = mainResourceURL.appendingPathComponent("cleanup_rules", isDirectory: true)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }

        return nil
    }
}
