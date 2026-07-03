import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.gargantua.core", category: "AppScanner")

/// Abstraction over running-process detection so the scanner can be unit-tested.
public protocol RunningAppChecking: Sendable {
    func isRunning(bundleID: String) -> Bool
}

/// Production implementation backed by `NSRunningApplication`.
public struct DefaultRunningAppChecker: RunningAppChecking {
    public init() {}

    public func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

/// Scans installed macOS applications and produces `AppInfo` records for the
/// Smart Uninstaller pipeline.
public protocol AppScanning: Sendable {
    func scanApps() async -> [AppInfo]
}

/// Default scanner: composes an enumerator, a bundle reader, a running-app
/// checker, and a code-signature verifier into a list of `AppInfo` records,
/// deduplicated by bundle identifier.
///
/// The scanner only *reads* — it never writes to `SafetyLevel` or any other
/// Trust Layer state. Consumers remain responsible for classifying remnants
/// downstream.
public struct DefaultAppScanner: AppScanning {
    private let enumerator: AppBundleEnumerating
    private let reader: AppBundleReading
    private let runningChecker: RunningAppChecking
    private let signatureVerifier: CodeSignatureVerifying
    private let systemAppPrefixes: [String]
    private let observer: (any ScanProgressObserving)?

    public init(
        enumerator: AppBundleEnumerating = DefaultAppBundleEnumerator(),
        reader: AppBundleReading = DefaultAppBundleReader(),
        runningChecker: RunningAppChecking = DefaultRunningAppChecker(),
        signatureVerifier: CodeSignatureVerifying = DefaultCodeSignatureVerifier(),
        systemAppPrefixes: [String] = ["/System/"],
        observer: (any ScanProgressObserving)? = nil
    ) {
        self.enumerator = enumerator
        self.reader = reader
        self.runningChecker = runningChecker
        self.signatureVerifier = signatureVerifier
        self.systemAppPrefixes = systemAppPrefixes
        self.observer = observer
    }

    public func scanApps() async -> [AppInfo] {
        let bundles = enumerator.enumerateBundles()
        logger.info("AppScanner: enumerated \(bundles.count, privacy: .public) bundle candidate(s)")

        // Per-bundle work — signature validation and recursive size measurement
        // — is independent and dominated by disk I/O, so run it concurrently: a
        // single huge bundle (Xcode) no longer serialises every smaller one
        // behind it. Results carry their original index, and a reorder buffer
        // replays them in enumeration order as each in-order prefix completes.
        // That keeps first-seen-wins dedup deterministic AND keeps the live
        // progress console streaming (rather than dumping every event at once
        // when the slow bundle finally lands).
        var byBundleID: [String: AppInfo] = [:]
        var order: [String] = []
        var pending: [Int: BundleScanOutcome] = [:]
        var nextToEmit = 0

        await withTaskGroup(of: (Int, BundleScanOutcome).self) { group in
            for (index, bundleURL) in bundles.enumerated() {
                group.addTask { (index, self.scanBundle(bundleURL)) }
            }
            for await (index, outcome) in group {
                pending[index] = outcome
                while let ready = pending.removeValue(forKey: nextToEmit) {
                    record(ready, into: &byBundleID, order: &order)
                    nextToEmit += 1
                }
            }
        }

        return order.compactMap { byBundleID[$0] }
    }

    /// Fold one bundle's outcome into the deduplicated result and emit its
    /// progress event. Called in enumeration order from the reorder buffer, so
    /// dedup precedence and event ordering match the original serial scan.
    private func record(
        _ outcome: BundleScanOutcome,
        into byBundleID: inout [String: AppInfo],
        order: inout [String]
    ) {
        switch outcome {
        case let .unreadable(path):
            logger.debug("AppScanner: skipping unreadable bundle at \(path, privacy: .public)")
            observer?.didEmit(ScanProgressEvent(path: path, outcome: .skipped(reason: "unreadable bundle")))
        case let .app(info, path, bytes):
            // Dedup: first-seen wins, so non-system search roots (e.g. /Applications)
            // take precedence over paths surfaced by NSRunningApplication.
            if byBundleID[info.bundleID] == nil {
                byBundleID[info.bundleID] = info
                order.append(info.bundleID)
                observer?.didEmit(ScanProgressEvent(path: path, outcome: .match, bytes: bytes))
            } else {
                observer?.didEmit(ScanProgressEvent(path: path, outcome: .skipped(reason: "duplicate bundleID")))
            }
        }
    }

    /// Outcome of scanning one bundle, carried out of the concurrent task group
    /// so dedup + progress emission can replay in deterministic order.
    private enum BundleScanOutcome {
        case unreadable(path: String)
        case app(AppInfo, path: String, bytes: Int64?)
    }

    private func scanBundle(_ bundleURL: URL) -> BundleScanOutcome {
        guard let metadata = reader.readMetadata(bundleURL: bundleURL) else {
            return .unreadable(path: bundleURL.path)
        }

        let signature = signatureVerifier.verify(bundleURL: bundleURL)
        let isRunning = runningChecker.isRunning(bundleID: metadata.bundleID)
        // `isSystemApp` is path-based only. Apple-distributed apps that live in
        // /Applications (Keynote, Pages, etc.) are user-installable/removable and
        // must not be flagged as system apps — doing so would let a naive caller
        // block their uninstallation even though the user can freely remove them.
        let isSystemApp = systemAppPrefixes.contains { bundleURL.path.hasPrefix($0) }
        let sizeOnDisk = reader.sizeOnDisk(bundleURL: bundleURL)

        let info = AppInfo(
            bundleID: metadata.bundleID,
            name: metadata.name,
            displayName: metadata.displayName,
            shortVersion: metadata.shortVersion,
            bundleVersion: metadata.bundleVersion,
            bundlePath: metadata.bundlePath,
            executablePath: metadata.executablePath,
            installDate: metadata.installDate,
            lastUsedDate: metadata.lastUsedDate,
            isRunning: isRunning,
            isSystemApp: isSystemApp,
            sizeOnDisk: sizeOnDisk,
            teamIdentifier: signature.teamIdentifier,
            signatureValid: signature.valid
        )
        return .app(info, path: bundleURL.path, bytes: sizeOnDisk)
    }
}
