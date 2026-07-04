import Foundation

/// Vends one `MCPScanSessionCache` per MCP connection so scan-session
/// item_ids stay isolated between clients. In dual-transport (`.both`) mode a
/// single process-wide cache let client A's `scan` item_ids be resolved by
/// client B's `clean`/`explain`; keying the cache by `MCPConnectionID` closes
/// that cross-client gap. Caches are created lazily on first use.
///
/// Lifecycle note: each SSE session's cache (its `MCPConnectionID` is a fresh
/// UUID minted per connect — see `MCPSSERequestRouter.openStream`) is retained
/// until `MCPSSERequestRouter.closeStream` teardown calls `evict(_:)`, which
/// drops the entry so a long-lived SSE daemon with heavy reconnect churn does
/// not accumulate orphaned scan-result sets for the process lifetime.
/// `.stdio` is never evicted — only SSE session teardown drives eviction.
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

    /// Evicts the cache for `connection`, dropping its retained scan-result
    /// set. Called on SSE session teardown (see `MCPSSERequestRouter.closeStream`)
    /// so a long-lived SSE daemon does not accumulate orphaned per-connection
    /// caches for the process lifetime. No-op if the connection has no cache.
    /// `.stdio` is a single lifetime session and is never evicted — the guard
    /// enforces that invariant even if the method is called directly.
    public func evict(_ connection: MCPConnectionID) {
        guard connection != .stdio else { return }
        lock.lock()
        defer { lock.unlock() }
        caches.removeValue(forKey: connection)
    }
}
