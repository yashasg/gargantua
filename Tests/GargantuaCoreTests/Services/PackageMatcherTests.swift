import Foundation
import Testing
@testable import GargantuaCore

@Suite("PackageMatcher")
struct PackageMatcherTests {
    private let matcher = PackageMatcher()

    private func app(
        bundleID: String,
        name: String,
        displayName: String? = nil,
        teamIdentifier: String? = nil
    ) -> AppInfo {
        AppInfo(
            bundleID: bundleID,
            name: name,
            displayName: displayName,
            bundlePath: "/Applications/\(name).app",
            teamIdentifier: teamIdentifier
        )
    }

    @Test("matches exact bundle ID and bundle-ID prefix children")
    func matchesExactAndBundlePrefix() {
        let docker = app(bundleID: "com.docker.docker", name: "Docker")
        let pkgs = [
            "com.docker.docker",
            "com.docker.docker.helper",
            "com.docker.compose",
        ]

        let matched = matcher.matches(packageIDs: pkgs, for: docker)

        #expect(matched == [
            "com.docker.docker",
            "com.docker.docker.helper",
            "com.docker.compose",
        ])
    }

    @Test("does not attribute sibling-vendor receipts to the app")
    func ignoresSharedVendorPrefix() {
        // Uninstalling Microsoft Word must not pull in Excel/Office receipts
        // just because they share the `com.microsoft.` vendor prefix — that is
        // the over-attribution that made bulk-accept trash a sibling app.
        let word = app(bundleID: "com.microsoft.Word", name: "Microsoft Word")
        let pkgs = [
            "com.microsoft.word",
            "com.microsoft.word.helper",
            "com.microsoft.excel",
            "com.microsoft.office.licensing",
        ]

        let matched = matcher.matches(packageIDs: pkgs, for: word)

        // Exact + bundle-prefix only; the vendor siblings are left alone.
        #expect(matched == ["com.microsoft.word", "com.microsoft.word.helper"])
    }

    @Test("does not collapse to com.* when bundle ID is a single component")
    func ignoresSingleComponentBundleID() {
        let weird = app(bundleID: "single", name: "Weird")
        let pkgs = ["com.docker.docker", "single", "single.helper"]

        let matched = matcher.matches(packageIDs: pkgs, for: weird)

        // Exact and prefix matches still apply, but no reverse-DNS expansion.
        #expect(matched == ["single", "single.helper"])
    }

    @Test("matches app-name slug as a delimited component, not substring")
    func matchesNameSlugAsComponent() {
        let docker = app(bundleID: "io.docker.docker", name: "Docker")
        let pkgs = [
            "com.example.docker.cli", // matches: docker is a component
            "com.example.dockerfile.tool", // does NOT match: dockerfile != docker
            "com.example.notrelated",
        ]

        let matched = matcher.matches(packageIDs: pkgs, for: docker)

        #expect(matched == ["com.example.docker.cli"])
    }

    @Test("ignores trivially short app names to keep noise down")
    func ignoresShortNameSlugs() {
        let go = app(bundleID: "io.example.go", name: "Go")
        let pkgs = [
            "com.golang.tools",
            "com.example.go.runtime",
            "io.example.go",
        ]

        let matched = matcher.matches(packageIDs: pkgs, for: go)

        // Only bundle-prefix and exact matches survive — the 2-char slug is dropped.
        #expect(matched == ["io.example.go"])
    }

    @Test("blocks com.apple.* and com.macports.* even when they superficially match")
    func blocksSystemPrefixes() {
        let appleFinder = app(bundleID: "com.apple.finder", name: "Finder")
        let pkgs = [
            "com.apple.finder",
            "com.apple.pkg.CoreTypes",
            "com.macports.MacPorts",
            "org.example.tool",
        ]

        let matched = matcher.matches(packageIDs: pkgs, for: appleFinder)

        #expect(matched == [])
        #expect(matcher.isSystemPackage("com.apple.finder"))
        #expect(matcher.isSystemPackage("com.macports.MacPorts"))
        #expect(!matcher.isSystemPackage("com.docker.docker"))
    }

    @Test("preserves input order in matches")
    func preservesInputOrder() {
        let docker = app(bundleID: "com.docker.docker", name: "Docker")
        let pkgs = [
            "com.docker.compose",
            "com.docker.docker",
            "com.docker.docker.helper",
        ]

        let matched = matcher.matches(packageIDs: pkgs, for: docker)

        #expect(matched == pkgs)
    }
}
