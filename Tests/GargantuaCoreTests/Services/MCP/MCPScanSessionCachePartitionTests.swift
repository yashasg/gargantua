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

    @Test("explain cannot resolve item_ids scanned by a different connection in dual-transport mode")
    func crossConnectionExplainRejectsUnknownID() throws {
        let (dispatcher, registry) = Self.makeDispatcherWithScan()

        let explainHandler = MCPExplainToolHandler(
            explainProvider: MCPExplainToolHandler.defaultFilesystemProvider(
                itemLookup: { id in registry.cache(for: dispatcher.currentCallConnection()).lookup(id: id) }
            )
        )
        dispatcher.register(tool: .explain, handler: explainHandler.toolHandler)

        let scanParams: MCPJSONAny = .object([
            "name": .string("scan"),
            "arguments": .object(["dry_run": .bool(true)]),
        ])
        _ = dispatcher.dispatch(request(method: "tools/call", params: scanParams), connection: .stdio)

        let explainParams: MCPJSONAny = .object([
            "name": .string("explain"),
            "arguments": .object(["item_id": .string("safe-a")]),
        ])

        // Client B, on a distinct SSE connection, never saw client A's scan —
        // its item_id must not resolve through explain either.
        let crossConnectionResponse = dispatcher.dispatch(
            request(method: "tools/call", params: explainParams),
            connection: .sse("client-b")
        )
        #expect(crossConnectionResponse?.error?.code == MCPErrorCode.invalidParams)
        #expect(crossConnectionResponse?.error?.message.contains("Unknown item_id") == true)

        // The original connection still resolves its own scan's item_ids.
        let sameConnectionResponse = dispatcher.dispatch(
            request(method: "tools/call", params: explainParams),
            connection: .stdio
        )
        #expect(sameConnectionResponse?.error == nil)
    }

    @Test("currentCallConnection reflects the dispatched connection and clears to .stdio afterward")
    func currentCallConnectionReflectsDispatchedConnection() {
        let dispatcher = MCPRequestDispatcher(
            serverInfo: Self.serverInfo,
            tools: MCPPhase2Tools.all + MCPPhase3Tools.all
        )
        // Outside any tool call the accessor falls back to `.stdio`.
        #expect(dispatcher.currentCallConnection() == .stdio)

        let captured = ConnectionCaptureBox()
        dispatcher.register(tool: .status) { _ in
            captured.value = dispatcher.currentCallConnection()
            return .failure("captured")
        }

        let statusParams: MCPJSONAny = .object(["name": .string("status")])
        _ = dispatcher.dispatch(
            request(method: "tools/call", params: statusParams),
            connection: .sse("client-z")
        )

        // During the call the handler saw the dispatched connection…
        #expect(captured.value == .sse("client-z"))
        // …and the thread-local is cleared back to the `.stdio` fallback after.
        #expect(dispatcher.currentCallConnection() == .stdio)
    }

    // MARK: - Helpers

    /// Builds a dispatcher with a `scan` handler wired to a fresh registry; the
    /// scanner returns a single known item (`safe-a`) so tests can reference its
    /// id without parsing the wire payload.
    private static func makeDispatcherWithScan() -> (MCPRequestDispatcher, MCPScanSessionCacheRegistry) {
        let dispatcher = MCPRequestDispatcher(
            serverInfo: serverInfo,
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
        return (dispatcher, registry)
    }
}

/// Mutable single-value box for capturing the in-call connection from a
/// `@Sendable` handler closure. Tests dispatch synchronously, so the plain
/// unsynchronized store is safe.
private final class ConnectionCaptureBox: @unchecked Sendable {
    var value: MCPConnectionID?
}
