import Foundation

/// Vends one `MCPScanSessionCache` per MCP connection so scan-session
/// item_ids stay isolated between clients. In dual-transport (`.both`) mode a
/// single process-wide cache let client A's `scan` item_ids be resolved by
/// client B's `clean`/`explain`; keying the cache by `MCPConnectionID` closes
/// that cross-client gap. Caches are created lazily on first use.
///
/// Lifecycle note: entries are never evicted, so each dead SSE session's cache
/// (its `MCPConnectionID` is a fresh UUID minted per connect — see
/// `MCPSSERequestRouter.openStream`) is retained for the process lifetime.
/// For stdio and low-churn SSE that is negligible, but a long-lived SSE daemon
/// with heavy reconnect churn accumulates orphaned scan-result sets. Wiring
/// `MCPSSERequestRouter.closeStream` teardown to registry eviction — alongside
/// the analogous never-evicted `MCPRequestDispatcher.clientIdentities` map — is
/// tracked as a follow-up (gargantua connection-lifecycle eviction).
public final class MCPScanSessionCacheRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var caches: [MCPConnectionID: MCPScanSessionCache] = [:]

    public init() {}

    /// The scan-session cache for `connection`, created on first request.
    /// Same id → same instance; distinct ids → isolated instances.
    public func cache(for connection: MCPConnectionID) -> MCPScanSessionCache {
        lock.lock()
        defer { lock.unlock() }
        if let existing = caches[connection] { return existing }
        let created = MCPScanSessionCache()
        caches[connection] = created
        return created
    }
}
