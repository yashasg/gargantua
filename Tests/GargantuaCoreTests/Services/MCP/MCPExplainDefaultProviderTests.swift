import Testing
import Foundation
@testable import GargantuaCore

@Suite("MCP explain default filesystem provider")
struct MCPExplainDefaultProviderTests {

    // MARK: Input validation

    @Test("unknown item_id is rejected with invalidParams")
    func unknownItemIdRejected() throws {
        // Default itemLookup returns nil — an id with no matching scan-session
        // entry is a client bug, not a silent no-op.
        let provider = MCPExplainToolHandler.defaultFilesystemProvider()
        do {
            _ = try provider(MCPExplainInput(itemId: "abc"))
            Issue.record("provider should have thrown")
        } catch MCPToolError.invalidParams(let message) {
            #expect(message.contains("item_id"))
            #expect(message.contains("abc"))
        }
    }

    @Test("known item_id resolves to the scan-time classification")
    func knownItemIdResolves() throws {
        let cached = ScanResult(
            id: "czkawka-broken_files-3",
            name: "broken.png",
            path: "/tmp/broken.png",
            size: 172_447,
            safety: .review,
            confidence: 55,
            explanation: "File appears corrupt. Verify before removing.",
            source: SourceAttribution(name: "Czkawka"),
            category: "broken_files"
        )
        let provider = MCPExplainToolHandler.defaultFilesystemProvider(
            itemLookup: { id in id == cached.id ? cached : nil }
        )

        let output = try provider(MCPExplainInput(itemId: cached.id))

        #expect(output.name == "broken.png")
        #expect(output.safety == "review")
        #expect(output.confidence == 55)
        #expect(output.explanation == "File appears corrupt. Verify before removing.")
        #expect(output.size != nil)
    }

    @Test("item_id resolution enriches the explanation with receipt provenance")
    func itemIdResolveSurfacesProvenance() throws {
        let cached = ScanResult(
            id: "native-app_cache-0",
            name: "Cache_Data",
            path: "/tmp/Cache_Data",
            size: 2_744_320,
            safety: .review,
            confidence: 82,
            explanation: "App cache.",
            source: SourceAttribution(name: "Application Support"),
            category: "app_cache"
        )
        let receipt = PackageReceipt(pkgID: "com.example.app", version: "1.2.3")
        let provider = MCPExplainToolHandler.defaultFilesystemProvider(
            receiptLookup: { _ in [receipt] },
            itemLookup: { _ in cached }
        )

        let output = try provider(MCPExplainInput(itemId: cached.id))

        #expect(output.receipts?.first?.pkgID == "com.example.app")
        #expect(output.explanation.contains("Owned by package com.example.app"))
        #expect(output.explanation.contains("App cache."))
    }

    @Test("empty path input is rejected with invalidParams")
    func emptyPathRejected() throws {
        let provider = MCPExplainToolHandler.defaultFilesystemProvider()
        do {
            _ = try provider(MCPExplainInput(path: ""))
            Issue.record("provider should have thrown")
        } catch MCPToolError.invalidParams {
            // expected
        }
    }

    @Test("relative path input is rejected with invalidParams (contract says absolute)")
    func relativePathRejected() throws {
        // MCPPhase2Tools.explain advertises path as an "Absolute filesystem
        // path". Accepting relative paths would silently resolve against the
        // MCP process CWD and produce surprising metadata depending on
        // launch context.
        let provider = MCPExplainToolHandler.defaultFilesystemProvider()
        do {
            _ = try provider(MCPExplainInput(path: "Documents/foo.txt"))
            Issue.record("provider should have thrown")
        } catch MCPToolError.invalidParams(let message) {
            #expect(message.lowercased().contains("absolute"))
        }
    }

    @Test("tilde path input is rejected (tilde is user-relative, not absolute)")
    func tildePathRejected() throws {
        let provider = MCPExplainToolHandler.defaultFilesystemProvider()
        do {
            _ = try provider(MCPExplainInput(path: "~/Documents"))
            Issue.record("provider should have thrown")
        } catch MCPToolError.invalidParams {
            // expected
        }
    }

    // MARK: Happy path — file

    @Test("absolute path to an existing file returns size + lastAccessed + basename")
    func existingFile() throws {
        let url = try Self.writeTempFile(bytes: 1024)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = MCPExplainToolHandler.defaultFilesystemProvider()
        let output = try provider(MCPExplainInput(path: url.path))

        #expect(output.name == url.lastPathComponent)
        #expect(output.safety == "review")
        #expect(output.confidence == 50)
        // AlertItem.formatBytes renders 1024B as "1.0 KB" (decimals are
        // kept for values < 10 of a unit, dropped otherwise).
        #expect(output.size == "1.0 KB")
        #expect(output.lastAccessed != nil)
        #expect(output.explanation.lowercased().contains("not yet wired"))
    }

    @Test("absolute path to an existing directory omits size but keeps lastAccessed")
    func existingDirectory() throws {
        // `.size` on a directory returns the inode size, not the recursive
        // total. The provider must omit that misleading value.
        let url = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = MCPExplainToolHandler.defaultFilesystemProvider()
        let output = try provider(MCPExplainInput(path: url.path))

        #expect(output.name == url.lastPathComponent)
        #expect(output.size == nil)
        #expect(output.lastAccessed != nil)
    }

    @Test("nonexistent absolute path returns a shell response with no metadata")
    func nonexistentPath() throws {
        // Shell contract: always render a conservative response for any
        // accepted input. A dedicated path-not-found signal lands with the
        // AI-backed provider that replaces this shell.
        let provider = MCPExplainToolHandler.defaultFilesystemProvider()
        let output = try provider(
            MCPExplainInput(path: "/this/path/does/not/exist/\(UUID().uuidString)")
        )
        #expect(output.safety == "review")
        #expect(output.confidence == 50)
        #expect(output.size == nil)
        #expect(output.lastAccessed == nil)
    }

    @Test("root path '/' returns basename '/' (URL.lastPathComponent edge case)")
    func rootPath() throws {
        let provider = MCPExplainToolHandler.defaultFilesystemProvider()
        let output = try provider(MCPExplainInput(path: "/"))
        // URL(fileURLWithPath: "/").lastPathComponent == "/", which the
        // provider's `isEmpty` guard already handles.
        #expect(!output.name.isEmpty)
    }

    // MARK: Receipt provenance

    @Test("receiptLookup yielding a receipt populates output.receipts and prepends provenance to explanation")
    func receiptsSurfaceProvenance() throws {
        let url = try Self.writeTempFile(bytes: 8)
        defer { try? FileManager.default.removeItem(at: url) }

        let receipt = PackageReceipt(
            pkgID: "com.docker.docker",
            version: "4.30.0",
            installDate: Date(timeIntervalSince1970: 1_701_734_400) // 2023-12-05Z
        )
        let provider = MCPExplainToolHandler.defaultFilesystemProvider(
            receiptLookup: { _ in [receipt] }
        )

        let output = try provider(MCPExplainInput(path: url.path))

        #expect(output.receipts?.count == 1)
        #expect(output.receipts?.first?.pkgID == "com.docker.docker")
        #expect(output.receipts?.first?.pkgVersion == "4.30.0")
        #expect(output.receipts?.first?.installDate == receipt.installDate)
        #expect(output.explanation.contains("Owned by package com.docker.docker"))
        #expect(output.explanation.contains("v4.30.0"))
        #expect(output.explanation.contains("2023-12-05"))
    }

    @Test("multiple receipts join with semicolons inside one provenance sentence")
    func multipleReceiptsJoinReadably() throws {
        let url = try Self.writeTempFile(bytes: 8)
        defer { try? FileManager.default.removeItem(at: url) }

        let receipts = [
            PackageReceipt(pkgID: "com.example.alpha", version: "1.0"),
            PackageReceipt(pkgID: "com.example.beta", version: "2.0"),
        ]
        let provider = MCPExplainToolHandler.defaultFilesystemProvider(
            receiptLookup: { _ in receipts }
        )

        let output = try provider(MCPExplainInput(path: url.path))

        #expect(output.receipts?.count == 2)
        #expect(output.explanation.contains("com.example.alpha"))
        #expect(output.explanation.contains("com.example.beta"))
        #expect(output.explanation.contains(";"))
    }

    @Test("empty receipt lookup leaves output.receipts nil and explanation untouched")
    func emptyReceiptsAreOmitted() throws {
        let url = try Self.writeTempFile(bytes: 8)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = MCPExplainToolHandler.defaultFilesystemProvider(
            receiptLookup: { _ in [] }
        )

        let output = try provider(MCPExplainInput(path: url.path))

        #expect(output.receipts == nil)
        #expect(!output.explanation.contains("Owned by package"))
    }

    @Test("default receiptLookup (no argument) yields no receipts")
    func defaultReceiptLookupYieldsNothing() throws {
        let url = try Self.writeTempFile(bytes: 8)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = MCPExplainToolHandler.defaultFilesystemProvider()
        let output = try provider(MCPExplainInput(path: url.path))

        #expect(output.receipts == nil)
    }

    // MARK: Rule-engine path classification

    @Test("a path the rule engine claims returns the real verdict, not the shell")
    func pathClassifyHitReturnsRealVerdict() throws {
        let url = try Self.writeTempFile(bytes: 8)
        defer { try? FileManager.default.removeItem(at: url) }

        let verdict = ScanResult(
            id: "system_logs-0",
            name: "CrashReporter",
            path: url.path,
            size: 4096,
            safety: .safe,
            confidence: 90,
            explanation: "Application log files. Safe to remove when not needed.",
            source: SourceAttribution(name: "macOS"),
            category: "system_logs"
        )
        let provider = MCPExplainToolHandler.defaultFilesystemProvider(
            pathClassify: { p in p == url.path ? verdict : nil }
        )

        let output = try provider(MCPExplainInput(path: url.path))

        #expect(output.safety == "safe")
        #expect(output.confidence == 90)
        #expect(output.explanation.contains("Safe to remove"))
        #expect(!output.explanation.contains("AI-backed analysis is not yet wired"))
    }

    @Test("a path no rule claims falls back to the AI-pending shell")
    func pathClassifyMissFallsBackToShell() throws {
        let url = try Self.writeTempFile(bytes: 8)
        defer { try? FileManager.default.removeItem(at: url) }

        let provider = MCPExplainToolHandler.defaultFilesystemProvider(
            pathClassify: { _ in nil }
        )

        let output = try provider(MCPExplainInput(path: url.path))

        #expect(output.safety == "review")
        #expect(output.explanation.contains("AI-backed analysis is not yet wired"))
    }

    // MARK: Wiring through the handler

    @Test("default provider wired through the handler produces a structured result")
    func wiringSmokeTest() throws {
        let url = try Self.writeTempFile(bytes: 10)
        defer { try? FileManager.default.removeItem(at: url) }

        let handler = MCPExplainToolHandler(
            explainProvider: MCPExplainToolHandler.defaultFilesystemProvider()
        )
        let result = try handler.handle(MCPToolArguments([
            "path": .string(url.path),
        ]))
        #expect(result.isError == false)
        #expect(result.structuredContent != nil)
    }

    // MARK: Fixtures

    private static func writeTempFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-explain-\(UUID().uuidString).bin")
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    private static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-explain-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
