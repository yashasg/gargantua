import Foundation
import Testing
@testable import GargantuaCore

/// Cross-app shared-receipt cases: one installer drops files used by multiple
/// still-installed apps (Adobe Creative Cloud, MS Office shapes). A receipt is
/// attributed to the uninstall target only when it is the target's *own*
/// receipt (exact bundle id or a dotted-child subpackage) — never on a shared
/// reverse-DNS vendor prefix, which would misattribute a sibling app's or a
/// shared installer's files to the target and let bulk-accept trash them.
/// Genuinely-owned receipt items still classify as `.review`/`.protected_`
/// (never `.safe`), with provenance pinned to the receipt's package ID.
@Suite("Cross-app shared-receipt evidence")
struct CrossAppSharedReceiptTests {

    private final class StubRunner: ProcessRunner, @unchecked Sendable {
        let outputs: [[String]: ProcessOutput]

        init(outputs: [[String]: ProcessOutput]) {
            self.outputs = outputs
        }

        func run(executable: URL, arguments: [String]) throws -> ProcessOutput {
            try run(executable: executable, arguments: arguments, timeout: nil)
        }

        func run(executable _: URL, arguments: [String], timeout _: TimeInterval?) throws -> ProcessOutput {
            outputs[arguments] ?? ProcessOutput(stdout: "", stderr: "", exitCode: 0)
        }
    }

    private final class Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("CrossAppSharedReceiptTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        @discardableResult
        func makeFile(_ relative: String, contents: String = "x") throws -> URL {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }

    /// Stub spec for one package's `pkgutil` triple (`--pkg-info` + `--files`).
    private struct PkgStub {
        let id: String
        let version: String
        let paths: [String]
    }

    /// Build a `StubRunner` from a list of `PkgStub`s. Emits `--pkgs` listing
    /// every id, plus matched `--pkg-info` and `--files` outputs. Paths are
    /// emitted with the leading `/` stripped so the expander resolves them
    /// against `volume: /` / `location: /`.
    private static func stubRunner(_ stubs: [PkgStub]) -> StubRunner {
        var outputs: [[String]: ProcessOutput] = [:]
        outputs[["--pkgs"]] = ProcessOutput(
            stdout: stubs.map(\.id).joined(separator: "\n"),
            stderr: "",
            exitCode: 0
        )
        for stub in stubs {
            outputs[["--pkg-info", stub.id]] = ProcessOutput(
                stdout: """
                package-id: \(stub.id)
                version: \(stub.version)
                volume: /
                location: /
                """,
                stderr: "",
                exitCode: 0
            )
            outputs[["--files", stub.id]] = ProcessOutput(
                stdout: stub.paths.map { String($0.dropFirst()) }.joined(separator: "\n"),
                stderr: "",
                exitCode: 0
            )
        }
        return StubRunner(outputs: outputs)
    }

    /// Build a receipt-evidence-enabled scanner around `runner` with a
    /// permissive (empty) `ProtectedRootPolicy` so the test controls every
    /// classification gate explicitly.
    private static func scanner(
        rules: [RemnantRule] = [],
        runner: StubRunner
    ) -> RemnantScanner {
        RemnantScanner(rules: rules).withReceiptEvidence(
            expander: PackageReceiptExpander(runner: runner),
            builder: ReceiptRemnantBuilder(protectedRoots: ProtectedRootPolicy(entries: []))
        )
    }

    private static func app(_ bundleID: String, _ name: String) -> AppInfo {
        AppInfo(bundleID: bundleID, name: name, bundlePath: "/Applications/\(name).app")
    }

    // MARK: - Adobe Creative Cloud shape

    @Test("Adobe shape: a shared-installer receipt is not attributed to the uninstall target")
    func adobeSharedInstallerReceiptNotAttributed() throws {
        let fixture = try Fixture()
        // Adobe Creative Cloud's shared installer (`com.adobe.acc.installer`)
        // drops a support file used across Adobe apps. The user is uninstalling
        // Photoshop, whose own receipt owns its own settings. The shared
        // installer's file must NOT be pulled in as a Photoshop remnant just
        // because it shares the `com.adobe.` vendor prefix — that misattribution
        // is what let bulk-accept trash files another Adobe app still needs.
        let ownedFile = try fixture.makeFile(
            "Library/Application Support/Adobe/Adobe Photoshop 2024/settings.dat",
            contents: "photoshop"
        )
        let sharedFile = try fixture.makeFile(
            "Library/Application Support/Adobe/AdobeApplicationManager/shared.bin",
            contents: "shared adobe state"
        )

        let runner = Self.stubRunner([
            PkgStub(id: "com.adobe.Photoshop", version: "25.0.0", paths: [ownedFile.path]),
            PkgStub(id: "com.adobe.acc.installer", version: "5.10", paths: [sharedFile.path]),
        ])
        let plan = Self.scanner(runner: runner).plan(
            for: Self.app("com.adobe.Photoshop", "Adobe Photoshop"),
            includeAppBundle: false
        )

        // Photoshop's own receipt file still surfaces as `.review` evidence,
        // with provenance pinned to Photoshop's own package id...
        let owned = try #require(plan.remnants.first { $0.path == ownedFile.path })
        #expect(owned.safety == .review)
        #expect(owned.ruleID == "pkgutil-bom:com.adobe.Photoshop")
        #expect(owned.tags.contains("pkgutil-bom"))
        // ...but the shared installer's file is never attributed to Photoshop.
        #expect(plan.remnants.contains { $0.path == sharedFile.path } == false)
    }

    @Test("Adobe shape: same path listed in two sibling receipts dedupes to a single row")
    func adobeDuplicatePathAcrossReceiptsDedups() throws {
        let fixture = try Fixture()
        let sharedFile = try fixture.makeFile(
            "Library/Application Support/Adobe/Common/Plug-ins/CommonPlugin.plugin",
            contents: "shared plugin"
        )

        // Both Photoshop and Illustrator receipts list the same shared plugin
        // path. Only one row should surface; first receipt processed wins.
        let runner = Self.stubRunner([
            PkgStub(id: "com.adobe.Photoshop", version: "25.0.0", paths: [sharedFile.path]),
            PkgStub(id: "com.adobe.Illustrator", version: "28.0.0", paths: [sharedFile.path]),
        ])
        let plan = Self.scanner(runner: runner).plan(
            for: Self.app("com.adobe.Photoshop", "Adobe Photoshop"),
            includeAppBundle: false
        )

        let hits = plan.remnants.filter { $0.path == sharedFile.path }
        #expect(hits.count == 1)
        #expect(hits.first?.ruleID == "pkgutil-bom:com.adobe.Photoshop")
    }

    @Test("Adobe shape: a sibling app's receipt is not attributed to the uninstall target")
    func adobeSiblingAppReceiptNotAttributed() throws {
        let fixture = try Fixture()
        // Illustrator is a still-installed sibling. Its receipt shares
        // Photoshop's `com.adobe.` vendor prefix but owns Illustrator's own
        // files. Uninstalling Photoshop must not surface — and so must not let
        // bulk-accept trash — a sibling app's files.
        let illustratorFile = try fixture.makeFile(
            "Library/Application Support/Adobe/Illustrator 2024/illustrator.dat",
            contents: "illustrator"
        )

        let runner = Self.stubRunner([
            PkgStub(id: "com.adobe.illustrator", version: "28.0.0", paths: [illustratorFile.path]),
        ])
        let plan = Self.scanner(runner: runner).plan(
            for: Self.app("com.adobe.Photoshop", "Adobe Photoshop"),
            includeAppBundle: false
        )

        #expect(plan.remnants.contains { $0.path == illustratorFile.path } == false)
    }

    // MARK: - MS Office shape

    @Test("MS Office shape: shared system path upgrades to .protected_ regardless of ownership")
    func msOfficeSharedLaunchDaemonProtected() throws {
        // MS Office's licensing helper is shared across Word, Excel, PowerPoint,
        // Outlook. Use the real `/Library/LaunchDaemons/` path the Office
        // installer drops; if it doesn't exist (most CI machines), the receipt
        // builder drops it as a stale-receipt case which is itself the correct
        // Trust Layer behavior.
        let sharedDaemon = "/Library/LaunchDaemons/com.microsoft.office.licensingV2.helper.plist"
        let pathExists = FileManager.default.fileExists(atPath: sharedDaemon)

        let runner = Self.stubRunner([
            PkgStub(id: "com.microsoft.package.Microsoft_Word.app", version: "16.80", paths: []),
            PkgStub(id: "com.microsoft.office.licensing", version: "16.80", paths: [sharedDaemon]),
        ])
        let plan = Self.scanner(runner: runner).plan(
            for: Self.app("com.microsoft.Word", "Microsoft Word"),
            includeAppBundle: false
        )

        if pathExists {
            // Shared system path overrides any ownership claim from the BOM.
            let item = try #require(plan.remnants.first { $0.path == sharedDaemon })
            #expect(item.safety == .protected_)
            #expect(item.explanation.contains("Shared system path"))
            #expect(item.ruleID == "pkgutil-bom:com.microsoft.office.licensing")
        } else {
            // No Office installed → stale receipt entry, silently dropped.
            #expect(plan.remnants.contains { $0.path == sharedDaemon } == false)
        }
    }

    @Test("MS Office shape: the shared licensing receipt is not attributed to the uninstall target")
    func msOfficeSharedLicensingReceiptNotAttributed() throws {
        let fixture = try Fixture()
        // The Office licensing receipt owns a font cache shared by Word, Excel,
        // and PowerPoint. Uninstalling Word must not surface it as a Word
        // remnant — this is the bean's exact example of the over-attribution
        // that endangered still-installed sibling apps.
        let sharedCache = try fixture.makeFile(
            "Library/Group Containers/UBF8T346G9.Office/FontCache.dat",
            contents: "font cache"
        )

        let runner = Self.stubRunner([
            PkgStub(id: "com.microsoft.package.Microsoft_Word.app", version: "16.80", paths: []),
            PkgStub(id: "com.microsoft.office.licensing", version: "16.80", paths: [sharedCache.path]),
        ])
        let plan = Self.scanner(runner: runner).plan(
            for: Self.app("com.microsoft.Word", "Microsoft Word"),
            includeAppBundle: false
        )

        #expect(plan.remnants.contains { $0.path == sharedCache.path } == false)
    }

    // MARK: - YAML rule precedence over receipt for shared paths

    @Test("YAML rule with explicit safety wins over receipt classification for cross-app shared path")
    func yamlRuleWinsOverReceiptForSharedPath() throws {
        let fixture = try Fixture()
        let sharedFile = try fixture.makeFile(
            "Library/Application Support/Adobe/Common/shared.bin",
            contents: "shared"
        )

        // A YAML remnant rule explicitly tags this path as `.safe` for
        // Photoshop. The receipt would default it to `.review`. Per existing
        // dedup behavior, the rule output is emitted first and the receipt
        // path is suppressed.
        let rule = RemnantRule(
            id: "adobe_common_shared",
            name: "Adobe shared common",
            category: .supportFiles,
            pathTemplates: [sharedFile.path],
            safety: .safe,
            confidence: 90,
            explanation: "Shared Adobe common files; rule-classified.",
            source: SourceAttribution(name: "Adobe", bundleID: "com.adobe.Photoshop"),
            appliesTo: AppScope(bundleIDs: ["com.adobe.Photoshop"])
        )

        let runner = Self.stubRunner([
            PkgStub(id: "com.adobe.acc.installer", version: "5.10", paths: [sharedFile.path]),
        ])
        let plan = Self.scanner(rules: [rule], runner: runner).plan(
            for: Self.app("com.adobe.Photoshop", "Adobe Photoshop"),
            includeAppBundle: false
        )

        let hits = plan.remnants.filter { $0.path == sharedFile.path }
        #expect(hits.count == 1)
        let item = try #require(hits.first)
        #expect(item.ruleID == "adobe_common_shared")
        #expect(!item.tags.contains("pkgutil-bom"))
    }
}
