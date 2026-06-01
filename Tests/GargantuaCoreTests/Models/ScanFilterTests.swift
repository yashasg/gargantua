import Foundation
import Testing
@testable import GargantuaCore

private func makeFilterResult(
    id: String,
    path: String,
    size: Int64,
    safety: SafetyLevel,
    category: String,
    bundleID: String? = nil
) -> ScanResult {
    ScanResult(
        id: id,
        name: "Item \(id)",
        path: path,
        size: size,
        safety: safety,
        confidence: 90,
        explanation: "Test item",
        source: SourceAttribution(name: "Test", bundleID: bundleID),
        category: category
    )
}

@Suite("ScanFilterSet")
struct ScanFilterSetTests {
    @Test("allow-listed decoder drops injected fields and invalid safety")
    func allowListedDecoderDropsUnknownFields() throws {
        let json = """
        {
          "bundle_ids": ["com.apple.dt.Xcode"],
          "path_globs": ["*/Developer/Xcode/*"],
          "categories": ["dev_artifacts"],
          "min_size": 1024,
          "max_size": 4096,
          "safety": ["safe", "root"],
          "mutate_safety": "protected_",
          "shell": "rm -rf ~"
        }
        """

        let filter = try #require(ScanFilterSet.decodeAllowListed(from: json))

        #expect(filter.bundleIDs == ["com.apple.dt.Xcode"])
        #expect(filter.pathGlobs == ["*/Developer/Xcode/*"])
        #expect(filter.categories == ["dev_artifacts"])
        #expect(filter.minimumSize == 1024)
        #expect(filter.maximumSize == 4096)
        #expect(filter.safetyLevels == [.safe])
    }

    @Test("applying filter matches DSL fields")
    func appliesAllFields() {
        let filter = ScanFilterSet(
            bundleIDs: ["com.apple.dt.Xcode"],
            pathGlobs: ["*/Developer/Xcode/*"],
            categories: ["dev_artifacts"],
            minimumSize: 1_000,
            maximumSize: 5_000,
            safetyLevels: [.review]
        )
        let matching = makeFilterResult(
            id: "match",
            path: "/Users/me/Library/Developer/Xcode/DerivedData/a",
            size: 2_000,
            safety: .review,
            category: "dev_artifacts",
            bundleID: "com.apple.dt.Xcode"
        )
        let wrongBundle = makeFilterResult(
            id: "bundle",
            path: matching.path,
            size: 2_000,
            safety: .review,
            category: "dev_artifacts",
            bundleID: "com.example.App"
        )
        let wrongSafety = makeFilterResult(
            id: "safety",
            path: matching.path,
            size: 2_000,
            safety: .safe,
            category: "dev_artifacts",
            bundleID: "com.apple.dt.Xcode"
        )

        #expect(filter.apply(to: [wrongBundle, matching, wrongSafety]).map(\.id) == ["match"])
    }

    @Test("applying filter does not mutate ScanResult safety")
    func applyingFilterDoesNotMutateSafety() {
        let result = makeFilterResult(
            id: "xcode",
            path: "/Users/me/Library/Developer/Xcode/DerivedData/a",
            size: 2_000,
            safety: .review,
            category: "dev_artifacts",
            bundleID: "com.apple.dt.Xcode"
        )
        let filter = ScanFilterSet(categories: ["dev_artifacts"], safetyLevels: [.review])

        let filtered = filter.apply(to: [result])

        #expect(result.safety == .review)
        #expect(filtered.count == 1)
        #expect(filtered.first?.safety == .review)
    }

    // MARK: - isEmpty (one field at a time)

    @Test("empty filter reports isEmpty; each single field makes it non-empty")
    func isEmptyIsTrueOnlyWhenEveryFieldIsUnset() {
        #expect(ScanFilterSet().isEmpty)
        #expect(!ScanFilterSet(bundleIDs: ["com.x"]).isEmpty)
        #expect(!ScanFilterSet(pathGlobs: ["*/x/*"]).isEmpty)
        #expect(!ScanFilterSet(categories: ["caches"]).isEmpty)
        #expect(!ScanFilterSet(minimumSize: 1).isEmpty)
        #expect(!ScanFilterSet(maximumSize: 1).isEmpty)
        #expect(!ScanFilterSet(safetyLevels: [.safe]).isEmpty)
    }

    @Test("empty filter is a pass-through; apply returns every result")
    func emptyFilterPassesEverythingThrough() {
        let results = [
            makeFilterResult(id: "a", path: "/a", size: 1, safety: .safe, category: "caches"),
            makeFilterResult(id: "b", path: "/b", size: 2, safety: .review, category: "logs"),
        ]
        #expect(ScanFilterSet().apply(to: results).map(\.id) == ["a", "b"])
    }

    // MARK: - bundleID matching (case-insensitive equality)

    @Test("bundleID matches case-insensitively but not when different")
    func bundleIDMatchingIsCaseInsensitive() {
        let filter = ScanFilterSet(bundleIDs: ["com.apple.dt.Xcode"])
        let exact = makeFilterResult(id: "x", path: "/x", size: 1, safety: .safe, category: "c", bundleID: "com.apple.dt.Xcode")
        let mixedCase = makeFilterResult(id: "u", path: "/u", size: 1, safety: .safe, category: "c", bundleID: "COM.APPLE.DT.XCODE")
        // Non-matches on BOTH sides of the filter value alphabetically, so the
        // == .orderedSame check can't be swapped for <= / >= and still pass.
        let before = makeFilterResult(id: "b", path: "/b", size: 1, safety: .safe, category: "c", bundleID: "com.aaa.app")
        let after = makeFilterResult(id: "a", path: "/a", size: 1, safety: .safe, category: "c", bundleID: "com.zzz.app")
        let noBundle = makeFilterResult(id: "n", path: "/n", size: 1, safety: .safe, category: "c", bundleID: nil)

        #expect(filter.matches(exact))
        #expect(filter.matches(mixedCase))
        #expect(!filter.matches(before))
        #expect(!filter.matches(after))
        #expect(!filter.matches(noBundle))
    }

    // MARK: - category matching (case-insensitive equality)

    @Test("category matches case-insensitively but not when different")
    func categoryMatchingIsCaseInsensitive() {
        let filter = ScanFilterSet(categories: ["Dev_Artifacts"])
        let exact = makeFilterResult(id: "x", path: "/x", size: 1, safety: .safe, category: "dev_artifacts")
        // Non-matches sorting before and after "dev_artifacts" so == .orderedSame
        // can't be swapped for an ordering operator and still pass.
        let before = makeFilterResult(id: "b", path: "/b", size: 1, safety: .safe, category: "aaa_caches")
        let after = makeFilterResult(id: "a", path: "/a", size: 1, safety: .safe, category: "zzz_logs")

        #expect(filter.matches(exact))
        #expect(!filter.matches(before))
        #expect(!filter.matches(after))
    }

    // MARK: - size bounds (inclusive comparisons)

    @Test("minimumSize is inclusive: equal passes, one-under fails")
    func minimumSizeBoundaryIsInclusive() {
        let filter = ScanFilterSet(minimumSize: 1_000)
        #expect(filter.matches(makeFilterResult(id: "eq", path: "/p", size: 1_000, safety: .safe, category: "c")))
        #expect(!filter.matches(makeFilterResult(id: "lo", path: "/p", size: 999, safety: .safe, category: "c")))
        #expect(filter.matches(makeFilterResult(id: "hi", path: "/p", size: 1_001, safety: .safe, category: "c")))
    }

    @Test("maximumSize is inclusive: equal passes, one-over fails")
    func maximumSizeBoundaryIsInclusive() {
        let filter = ScanFilterSet(maximumSize: 2_000)
        #expect(filter.matches(makeFilterResult(id: "eq", path: "/p", size: 2_000, safety: .safe, category: "c")))
        #expect(!filter.matches(makeFilterResult(id: "hi", path: "/p", size: 2_001, safety: .safe, category: "c")))
        #expect(filter.matches(makeFilterResult(id: "lo", path: "/p", size: 1_999, safety: .safe, category: "c")))
    }

    // MARK: - cleanStrings (cap, dedup, trim)

    @Test("string lists are capped at 12, deduped case-insensitively, and trimmed")
    func cleanStringsCapsDedupsAndTrims() {
        // 13 distinct values → capped to 12.
        let many = (1 ... 13).map { "com.app.\($0)" }
        #expect(ScanFilterSet(bundleIDs: many).bundleIDs.count == 12)
        #expect(ScanFilterSet(bundleIDs: many).bundleIDs == Array(many.prefix(12)))

        // Case-insensitive dedup keeps the first spelling.
        let deduped = ScanFilterSet(categories: ["Caches", "caches", "CACHES"]).categories
        #expect(deduped == ["Caches"])

        // Whitespace trimmed, blanks and >256-char values dropped.
        let cleaned = ScanFilterSet(pathGlobs: ["  */x/*  ", "   ", String(repeating: "a", count: 257)]).pathGlobs
        #expect(cleaned == ["*/x/*"])
    }

    // MARK: - decodeAllowListed / firstJSONObject brace scanner

    @Test("JSON embedded after prose is extracted by the brace scanner")
    func decodesJSONWithLeadingProse() throws {
        let text = "Sure, here is the filter: {\"categories\":[\"caches\"],\"min_size\":10} — let me know!"
        let filter = try #require(ScanFilterSet.decodeAllowListed(from: text))
        #expect(filter.categories == ["caches"])
        #expect(filter.minimumSize == 10)
    }

    @Test("nested objects don't terminate extraction early")
    func decodesJSONWithNestedObject() throws {
        let text = "prefix {\"path_globs\":[\"x\"],\"ignored\":{\"a\":1},\"max_size\":99} suffix"
        let filter = try #require(ScanFilterSet.decodeAllowListed(from: text))
        #expect(filter.pathGlobs == ["x"])
        #expect(filter.maximumSize == 99)
    }

    @Test("a brace inside a string value is not counted by the depth scanner")
    func braceInsideStringIsIgnored() throws {
        let text = "note: {\"categories\":[\"a}b\"],\"min_size\":1} end"
        let filter = try #require(ScanFilterSet.decodeAllowListed(from: text))
        #expect(filter.categories == ["a}b"])
        #expect(filter.minimumSize == 1)
    }

    @Test("an escaped quote inside a string keeps the scanner in-string")
    func escapedQuoteInsideStringIsHandled() throws {
        // JSON value is the literal: a"}b  (escaped quote, then a brace)
        let text = #"note: {"path_globs":["a\"}b"],"min_size":1} end"#
        let filter = try #require(ScanFilterSet.decodeAllowListed(from: text))
        #expect(filter.pathGlobs == [#"a"}b"#])
        #expect(filter.minimumSize == 1)
    }

    @Test("an unterminated object yields no filter")
    func unterminatedObjectReturnsNil() {
        #expect(ScanFilterSet.decodeAllowListed(from: "broken {\"categories\":[\"caches\"") == nil)
    }

    @Test("text with no JSON object yields no filter")
    func garbageReturnsNil() {
        #expect(ScanFilterSet.decodeAllowListed(from: "no json here at all") == nil)
    }
}
