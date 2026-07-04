import Testing
import Foundation
@testable import GargantuaCore

/// Covers the dual-transport (`.both`) cross-client leak fix: `MCPScanSessionCache`
/// used to be a single process-wide instance shared by every connection, so
/// client A's `scan` item_ids were resolvable by client B's `clean`/`explain`.
/// `MCPScanSessionCacheRegistry` partitions the cache per `MCPConnectionID`; these
/// tests cover both the registry in isolation and the end-to-end dispatcher wiring.
@Suite("MCP scan-session cache partitioning")
struct MCPScanSessionCachePartitionTests {
    private static let serverInfo = MCPServerInfo(name: "gargantua", version: "0.0.1")

    private func request(
        id: MCPRequestID? = .int(1),
        method: String,
        params: MCPJSONAny? = nil
    ) -> MCPRequest {
        MCPRequest(id: id, method: method, params: params)
    }

    @Test("registry vends the same instance for the same connection and distinct instances across connections")
    func registryPartitionsByConnection() {
        let registry = MCPScanSessionCacheRegistry()
        #expect(registry.cache(for: .stdio) === registry.cache(for: .stdio))
        #expect(registry.cache(for: .stdio) !== registry.cache(for: .sse("x")))
    }

    @Test("clean cannot resolve item_ids scanned by a different connection in dual-transport mode")
    func crossConnectionCleanRejectsUnknownID() throws {
        let dispatcher = MCPRequestDispatcher(
            serverInfo: Self.serverInfo,
            tools: MCPPhase2Tools.all + MCPPhase3Tools.all
        )
        let registry = MCPScanSessionCacheRegistry()

        let scanHandler = MCPScanToolHandler(
            scanner: { _ in
                [
                    ScanResult(
                        id: "safe-a",
                        name: "cache-a",
                        path: "/tmp/cache/a",
                        size: 10_000,
                        safety: .safe,
                        confidence: 95,
                        explanation: "Browser cache",
                        source: SourceAttribution(name: "Safari"),
                        category: "browser_cache"
                    ),
                ]
            },
            profileResolver: { _ in .light },
            sessionCacheProvider: { registry.cache(for: dispatcher.currentCallConnection()) }
        )
        dispatcher.register(tool: .scan, handler: scanHandler.toolHandler)

        let cleanHandler = MCPCleanToolHandler(
            sessionCacheProvider: { registry.cache(for: dispatcher.currentCallConnection()) },
            cleaner: { items, method in
                CleanupResult(
                    itemResults: items.map { CleanupItemResult(item: $0, succeeded: true) },
                    cleanupMethod: method
                )
            }
        )
        dispatcher.register(tool: .clean, handler: cleanHandler.toolHandler)

        let scanParams: MCPJSONAny = .object([
            "name": .string("scan"),
            "arguments": .object(["dry_run": .bool(true)]),
        ])
        let scanResponse = dispatcher.dispatch(
            request(method: "tools/call", params: scanParams),
            connection: .stdio
        )
        #expect(scanResponse?.error == nil)

        let cleanParams: MCPJSONAny = .object([
            "name": .string("clean"),
            "arguments": .object([
                "item_ids": .array([.string("safe-a")]),
                "method": .string("trash"),
                "confirm": .bool(true),
                "dry_run": .bool(true),
            ]),
        ])

        // Client B, on a distinct SSE connection, never saw client A's scan —
        // its item_id must not resolve.
        let crossConnectionResponse = dispatcher.dispatch(
            request(method: "tools/call", params: cleanParams),
            connection: .sse("client-b")
        )
        #expect(crossConnectionResponse?.error?.code == MCPErrorCode.invalidParams)
        #expect(crossConnectionResponse?.error?.message.contains("Unknown item_id") == true)

        // The original connection still resolves its own scan's item_ids.
        let sameConnectionResponse = dispatcher.dispatch(
            request(method: "tools/call", params: cleanParams),
            connection: .stdio
        )
        #expect(sameConnectionResponse?.error == nil)
    }
}
