import Testing
import Foundation
@testable import GargantuaCore

@Suite("NativeScanAdapter.classify(path:) — single-path reverse matching")
struct NativeScanAdapterClassifyTests {

    // MARK: - globMatches pure-function tests

    @Test("globMatches handles *, **, ? and segment boundaries")
    func globMatchesSemantics() {
        let m = NativeScanAdapter.globMatches

        // `*` stays within one segment.
        #expect(m("/a/*/c", "/a/b/c"))
        #expect(!m("/a/*/c", "/a/b/x/c"))
        #expect(m("/a/*.log", "/a/server.log"))
        #expect(!m("/a/*.log", "/a/sub/server.log"))

        // `**` spans zero or more segments.
        #expect(m("/a/**/c", "/a/c"))
        #expect(m("/a/**/c", "/a/b/c"))
        #expect(m("/a/**/c", "/a/b/d/e/c"))
        #expect(m("/a/**", "/a/b/c/d"))

        // `?` matches exactly one character.
        #expect(m("/a/f?o", "/a/foo"))
        #expect(!m("/a/f?o", "/a/fooo"))

        // Literal mismatch.
        #expect(!m("/a/b", "/a/c"))
        #expect(m("/a/b", "/a/b"))
    }

    // MARK: - classify integration (real temp files)

    @Test("glob rule claims a matching file and returns its verdict")
    func globRuleMatchesFile() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let file = "\(dir)/server.log"
        try "x".write(toFile: file, atomically: true, encoding: .utf8)

        let rule = Self.rule(id: "logs", paths: ["\(dir)/*.log"], safety: .safe, category: "system_logs")
        let adapter = NativeScanAdapter(rules: [rule], profile: .deep)

        let result = adapter.classify(path: file)
        #expect(result?.safety == .safe)
        #expect(result?.path == file)
        #expect(result?.explanation == "test explanation")

        // A sibling the glob doesn't cover gets no verdict.
        let other = "\(dir)/notes.txt"
        try "y".write(toFile: other, atomically: true, encoding: .utf8)
        #expect(adapter.classify(path: other) == nil)
    }

    @Test("pattern rule selects children by filename pattern")
    func patternRuleSelectsChildren() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dmg = "\(dir)/Install.dmg"
        let txt = "\(dir)/readme.txt"
        try "x".write(toFile: dmg, atomically: true, encoding: .utf8)
        try "y".write(toFile: txt, atomically: true, encoding: .utf8)

        let rule = Self.rule(
            id: "dmgs", paths: [dir], pattern: "*.dmg", safety: .review, category: "installers"
        )
        let adapter = NativeScanAdapter(rules: [rule], profile: .deep)

        #expect(adapter.classify(path: dmg)?.safety == .review)
        #expect(adapter.classify(path: txt) == nil)
    }

    @Test("exclude suppresses an otherwise-matching child")
    func excludeSuppressesMatch() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let keep = "\(dir)/keep-me.cache"
        let junk = "\(dir)/junk.cache"
        try "x".write(toFile: keep, atomically: true, encoding: .utf8)
        try "y".write(toFile: junk, atomically: true, encoding: .utf8)

        let rule = Self.rule(
            id: "caches", paths: [dir], pattern: "*.cache", exclude: ["keep-*"],
            safety: .safe, category: "app_cache"
        )
        let adapter = NativeScanAdapter(rules: [rule], profile: .deep)

        #expect(adapter.classify(path: junk)?.safety == .safe)
        #expect(adapter.classify(path: keep) == nil)
    }

    @Test("** glob claims a deeply nested directory")
    func doubleStarMatchesNested() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let nested = "\(dir)/a/b/build"
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
        try "x".write(toFile: "\(nested)/artifact.o", atomically: true, encoding: .utf8)

        let rule = Self.rule(
            id: "builds", paths: ["\(dir)/**/build"], safety: .review, category: "dev_artifacts"
        )
        let adapter = NativeScanAdapter(rules: [rule], profile: .deep)

        #expect(adapter.classify(path: nested)?.safety == .review)
    }

    @Test("a path outside the active profile's categories gets no verdict")
    func profileCategoryGating() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let file = "\(dir)/server.log"
        try "x".write(toFile: file, atomically: true, encoding: .utf8)

        let rule = Self.rule(id: "logs", paths: ["\(dir)/*.log"], safety: .safe, category: "system_logs")
        // Profile scoped to a different category — the rule should not run.
        let profile = CleanupProfile(
            id: "narrow", name: "Narrow", description: "", categories: ["browser_cache"]
        )
        let adapter = NativeScanAdapter(rules: [rule], profile: profile)

        #expect(adapter.classify(path: file) == nil)
    }

    @Test("no rule matching the path yields nil")
    func noMatchYieldsNil() throws {
        let dir = try Self.tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let file = "\(dir)/server.log"
        try "x".write(toFile: file, atomically: true, encoding: .utf8)

        let rule = Self.rule(
            id: "elsewhere", paths: ["/nonexistent/place/*.log"], safety: .safe, category: "system_logs"
        )
        let adapter = NativeScanAdapter(rules: [rule], profile: .deep)
        #expect(adapter.classify(path: file) == nil)
    }

    // MARK: - Fixtures

    private static func tempDir() throws -> String {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("garg-classify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.path
    }

    private static func rule(
        id: String,
        paths: [String],
        pattern: String? = nil,
        exclude: [String] = [],
        safety: SafetyLevel,
        category: String
    ) -> ScanRule {
        ScanRule(
            id: id,
            name: "name-\(id)",
            paths: paths,
            pattern: pattern,
            exclude: exclude,
            safety: safety,
            confidence: 90,
            explanation: "test explanation",
            source: SourceAttribution(name: "Test"),
            category: category
        )
    }
}
