import Foundation
import GargantuaLicensing

#if canImport(AppKit)
    import AppKit
#endif

/// Production reader/writer for the user-domain `com.apple.Spotlight`
/// `EnabledPreferenceRules` store.
///
/// `EnabledPreferenceRules` is a dictionary keyed by rule identifier (a
/// reverse-DNS bundle id or a `System.*` / `com.apple.*` system rule) whose
/// values are per-rule settings dictionaries. We treat the keys as the rule
/// identifiers and rewrite the dictionary in place, preserving each retained
/// rule's settings untouched.
///
/// - Important: This mutates a live macOS preference domain. The shape above
///   should be confirmed on-device before the write path is surfaced in the UI;
///   callers default to `dryRun` until then.
public struct CFPreferencesSpotlightRulesStore: SpotlightRulesReading, SpotlightRulesWriting {
    public static let domain = "com.apple.Spotlight"
    public static let key = "EnabledPreferenceRules"

    public init() {}

    private func rulesDictionary() -> [String: Any] {
        let value = CFPreferencesCopyAppValue(
            Self.key as CFString,
            Self.domain as CFString
        )
        return (value as? [String: Any]) ?? [:]
    }

    public func enabledRuleIdentifiers() -> [String] {
        Array(rulesDictionary().keys)
    }

    public func write(keptIdentifiers: [String]) throws {
        let keep = Set(keptIdentifiers)
        let filtered = rulesDictionary().filter { keep.contains($0.key) }
        CFPreferencesSetAppValue(
            Self.key as CFString,
            filtered as CFDictionary,
            Self.domain as CFString
        )
        guard CFPreferencesAppSynchronize(Self.domain as CFString) else {
            throw SpotlightRulesStoreError.synchronizeFailed
        }
    }
}

public enum SpotlightRulesStoreError: Error, Sendable, Equatable {
    case synchronizeFailed
}

/// Resolves installed apps via LaunchServices through `NSWorkspace`.
public struct WorkspaceInstalledAppResolver: InstalledAppResolving {
    public init() {}

    public func isInstalled(bundleID: String) -> Bool {
        #if canImport(AppKit)
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        #else
            return false
        #endif
    }
}

extension SpotlightOrphanRuleScanner {
    /// Wires the production CFPreferences store, LaunchServices resolver, and
    /// the licensing destructive-action gate.
    public static func live() -> SpotlightOrphanRuleScanner {
        let store = CFPreferencesSpotlightRulesStore()
        return SpotlightOrphanRuleScanner(
            reader: store,
            writer: store,
            resolver: WorkspaceInstalledAppResolver(),
            canExecuteDestructive: {
                if case .allowed = await LicenseGate.shared.canExecuteDestructiveAction() {
                    return true
                }
                return false
            }
        )
    }
}
