import Testing
import Foundation
@testable import GargantuaCore

/// Covers SSE connection-teardown eviction: `gargantua-rupy` partitioned the
/// scan-session cache and client identity per `MCPConnectionID`, but neither
/// map was ever evicted, so a long-lived SSE daemon with heavy reconnect
/// churn would accumulate orphaned per-connection state for the process
/// lifetime. `MCPSSERequestRouter.closeStream` now fires an `onClose` hook
/// that drops both the registry's cache and the dispatcher's captured
/// identity for the closed session — `.stdio` is never touched because only
/// SSE session teardown drives eviction.
@Suite("MCP connection-teardown eviction")
struct MCPConnectionTeardownEvictionTests {
    private static let serverInfo = MCPServerInfo(name: "gargantua", version: "0.0.1")

    private func request(
        id: MCPRequestID? = .int(1),
        method: String,
        params: MCPJSONAny? = nil
    ) -> MCPRequest {
        MCPRequest(id: id, method: method, params: params)
    }

    private func initializeParams(clientName: String) -> MCPJSONAny {
        .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object([:]),
            "clientInfo": .object([
                "name": .string(clientName),
                "version": .string("1.0"),
            ]),
        ])
    }

    private static let scanParams: MCPJSONAny = .object([
        "name": .string("scan"),
        "arguments": .object(["dry_run": .bool(true)]),
    ])

    private static func cleanParams(itemID: String) -> MCPJSONAny {
        .object([
            "name": .string("clean"),
            "arguments": .object([
                "item_ids": .array([.string(itemID)]),
                "method": .string("trash"),
                "confirm": .bool(true),
                "dry_run": .bool(true),
            ]),
        ])
    }

    /// Registers a `scan` handler on `dispatcher` whose scanner always
    /// returns a single known item (`safe-a`), backed by `registry` the same
    /// way `main.swift` wires it: `registry.cache(for:
    /// dispatcher.currentCallConnection())`.
    private func registerScanHandler(
        dispatcher: MCPRequestDispatcher,
        registry: MCPScanSessionCacheRegistry
    ) {
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
    }

    /// Registers a `clean` handler exactly as `main.swift` wires it, minus
    /// the audit/rate-limit/notification plumbing: resolves the calling
    /// connection's cache and always reports success.
    private func registerCleanHandler(
        dispatcher: MCPRequestDispatcher,
        registry: MCPScanSessionCacheRegistry
    ) {
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
    }

    @Test("evict drops the cache; a fresh empty instance is vended afterward")
    func evictDropsCacheAndVendsFreshInstance() {
        let registry = MCPScanSessionCacheRegistry()
        let c1 = registry.cache(for: .sse("s1"))

        registry.evict(.sse("s1"))
        let c2 = registry.cache(for: .sse("s1"))

        #expect(c1 !== c2)
        #expect(c2.isEmpty)
    }

    @Test("evictClientIdentity clears the captured identity")
    func evictClientIdentityClearsIdentity() {
        let dispatcher = MCPRequestDispatcher(serverInfo: Self.serverInfo)

        _ = dispatcher.dispatch(
            request(method: "initialize", params: initializeParams(clientName: "client-A")),
            connection: .sse("s1")
        )
        #expect(dispatcher.currentClientIdentity(for: .sse("s1")) != nil)

        dispatcher.evictClientIdentity(for: .sse("s1"))
        #expect(dispatcher.currentClientIdentity(for: .sse("s1")) == nil)
    }

    @Test("closeStream fires onClose with the session's connection id")
    func closeStreamFiresOnCloseWithConnectionID() {
        let box = ConnectionCaptureBox()
        let router = MCPSSERequestRouter(
            handler: { _, _ in nil },
            onClose: { connection in box.value = connection }
        )

        router.closeStream(sessionID: "s1")

        #expect(box.value == .sse("s1"))
    }

    @Test("SSE teardown evicts both maps; a reused session cannot resolve the closed session's item_ids")
    func sseTeardownEvictsBothMapsEndToEnd() throws {
        let dispatcher = MCPRequestDispatcher(
            serverInfo: Self.serverInfo,
            tools: MCPPhase2Tools.all + MCPPhase3Tools.all
        )
        let registry = MCPScanSessionCacheRegistry()
        registerScanHandler(dispatcher: dispatcher, registry: registry)
        registerCleanHandler(dispatcher: dispatcher, registry: registry)

        let router = MCPSSERequestRouter(
            handler: { request, connection in dispatcher.dispatch(request, connection: connection) },
            onClose: { connection in
                registry.evict(connection)
                dispatcher.evictClientIdentity(for: connection)
            }
        )

        _ = dispatcher.dispatch(
            request(method: "initialize", params: initializeParams(clientName: "client-A")),
            connection: .sse("s1")
        )
        let scanResponse = dispatcher.dispatch(
            request(method: "tools/call", params: Self.scanParams),
            connection: .sse("s1")
        )
        #expect(scanResponse?.error == nil)
        #expect(dispatcher.currentClientIdentity(for: .sse("s1")) != nil)

        router.closeStream(sessionID: "s1")

        #expect(dispatcher.currentClientIdentity(for: .sse("s1")) == nil)
        #expect(registry.cache(for: .sse("s1")).isEmpty)

        let cleanResponse = dispatcher.dispatch(
            request(method: "tools/call", params: Self.cleanParams(itemID: "safe-a")),
            connection: .sse("s1")
        )
        #expect(cleanResponse?.error?.code == MCPErrorCode.invalidParams)
        #expect(cleanResponse?.error?.message.contains("Unknown item_id") == true)
    }

    @Test(".stdio state survives an SSE session close")
    func stdioSurvivesSSESessionClose() throws {
        let dispatcher = MCPRequestDispatcher(
            serverInfo: Self.serverInfo,
            tools: MCPPhase2Tools.all + MCPPhase3Tools.all
        )
        let registry = MCPScanSessionCacheRegistry()
        registerScanHandler(dispatcher: dispatcher, registry: registry)
        registerCleanHandler(dispatcher: dispatcher, registry: registry)

        let router = MCPSSERequestRouter(
            handler: { request, connection in dispatcher.dispatch(request, connection: connection) },
            onClose: { connection in
                registry.evict(connection)
                dispatcher.evictClientIdentity(for: connection)
            }
        )

        _ = dispatcher.dispatch(
            request(method: "initialize", params: initializeParams(clientName: "client-stdio")),
            connection: .stdio
        )
        let scanResponse = dispatcher.dispatch(
            request(method: "tools/call", params: Self.scanParams),
            connection: .stdio
        )
        #expect(scanResponse?.error == nil)
        let stdioCacheBeforeClose = registry.cache(for: .stdio)

        // Close an SSE session that was never opened on this router — closeStream
        // is a no-op for the routing table but must still fire onClose so this
        // exercises the real eviction path against an unrelated `.stdio` state.
        router.closeStream(sessionID: "s1")

        #expect(registry.cache(for: .stdio) === stdioCacheBeforeClose)
        #expect(dispatcher.currentClientIdentity(for: .stdio) != nil)
    }
}

/// Mutable single-value box for capturing the closed connection id from a
/// `@Sendable` `onClose` closure. Tests dispatch synchronously, so the plain
/// unsynchronized store is safe. Mirrors `ConnectionCaptureBox` in
/// `MCPScanSessionCachePartitionTests`.
private final class ConnectionCaptureBox: @unchecked Sendable {
    var value: MCPConnectionID?
}
