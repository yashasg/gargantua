import Testing
import Foundation
@testable import GargantuaCore

/// Covers the dual-transport (`.both`) trust-boundary fix: client identity is
/// captured and read back per `MCPConnectionID`, so a later `initialize` on one
/// transport can no longer overwrite the other transport's attribution and
/// mis-stamp the next destructive tool call's audit entry / rate-limit shard.
@Suite("MCP request dispatcher per-connection identity")
struct MCPRequestDispatcherConnectionTests {
    private static let serverInfo = MCPServerInfo(name: "gargantua", version: "0.0.1")

    private func makeDispatcher() -> MCPRequestDispatcher {
        MCPRequestDispatcher(serverInfo: Self.serverInfo)
    }

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

    @Test("initialize captures identity independently per connection")
    func perConnectionCapture() {
        let dispatcher = makeDispatcher()
        let connectionA = MCPConnectionID.stdio
        let connectionB = MCPConnectionID.sse("session-B")

        _ = dispatcher.dispatch(
            request(method: "initialize", params: initializeParams(clientName: "client-A")),
            connection: connectionA
        )
        _ = dispatcher.dispatch(
            request(method: "initialize", params: initializeParams(clientName: "client-B")),
            connection: connectionB
        )

        // B's handshake must not clobber A's captured identity.
        #expect(dispatcher.currentClientIdentity(for: connectionA)?.name == "client-A")
        #expect(dispatcher.currentClientIdentity(for: connectionB)?.name == "client-B")
    }

    @Test("re-initialize without clientInfo clears only its own connection")
    func reinitializeIsolation() {
        let dispatcher = makeDispatcher()
        let connectionA = MCPConnectionID.stdio
        let connectionB = MCPConnectionID.sse("session-B")

        _ = dispatcher.dispatch(
            request(method: "initialize", params: initializeParams(clientName: "client-A")),
            connection: connectionA
        )
        _ = dispatcher.dispatch(
            request(method: "initialize", params: initializeParams(clientName: "client-B")),
            connection: connectionB
        )

        // B re-initializes with no clientInfo — clears B, leaves A intact.
        let noClientInfo: MCPJSONAny = .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object([:]),
        ])
        _ = dispatcher.dispatch(
            request(method: "initialize", params: noClientInfo),
            connection: connectionB
        )

        #expect(dispatcher.currentClientIdentity(for: connectionA)?.name == "client-A")
        #expect(dispatcher.currentClientIdentity(for: connectionB) == nil)
    }

    @Test("tools/call on each connection attributes to that connection's client, not last-initialize-wins")
    func toolCallAttributionIsPerConnection() {
        let dispatcher = makeDispatcher()
        let connectionA = MCPConnectionID.stdio
        let connectionB = MCPConnectionID.sse("session-B")

        // A destructive-style tool that reads the identity the way the real
        // `clean` handler does: through `currentCallClientIdentity()`, which
        // must reflect the connection making THIS call.
        final class Seen: @unchecked Sendable {
            var names: [String] = []
        }
        let seen = Seen()
        dispatcher.register(tool: .clean) { _ in
            seen.names.append(dispatcher.currentCallClientIdentity()?.name ?? "unknown")
            return .text("ok")
        }

        _ = dispatcher.dispatch(
            request(method: "initialize", params: initializeParams(clientName: "client-A")),
            connection: connectionA
        )
        _ = dispatcher.dispatch(
            request(method: "initialize", params: initializeParams(clientName: "client-B")),
            connection: connectionB
        )

        // Interleave: B initialized most recently, but a call on A must still
        // attribute to A (the bug was: A's call would be stamped "client-B").
        let call: MCPJSONAny = .object(["name": .string("clean")])
        _ = dispatcher.dispatch(request(method: "tools/call", params: call), connection: connectionA)
        _ = dispatcher.dispatch(request(method: "tools/call", params: call), connection: connectionB)

        #expect(seen.names == ["client-A", "client-B"])
    }

    @Test("currentCallClientIdentity is nil outside a tool call")
    func currentCallIdentityNilOutsideCall() {
        let dispatcher = makeDispatcher()
        #expect(dispatcher.currentCallClientIdentity() == nil)
    }
}
