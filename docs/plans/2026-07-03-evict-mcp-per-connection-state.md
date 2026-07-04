# Evict MCP per-connection state on connection teardown — Implementation Plan

**Goal:** Evict an SSE session's scan-session cache and captured client identity when its stream tears down, so a long-lived SSE daemon stops accumulating orphaned per-connection state for the process lifetime.

**Approach:** `MCPSSERequestRouter.closeStream(sessionID:)` is already the single SSE teardown funnel (driven by `MCPSSETransport`'s connection `stateUpdateHandler` on `.cancelled`/`.failed`). Thread an `onClose` eviction closure through `MCPSSETransport.init` → `MCPSSERequestRouter.init` (mirroring the existing `handler` closure idiom, so `GargantuaCore` stays decoupled from the concrete registry/dispatcher). `closeStream` invokes it with `.sse(sessionID)` after releasing its own lock; `main.swift` wires it to drop the entry from both the `MCPScanSessionCacheRegistry` and the dispatcher's `clientIdentities` map. `.stdio` is never evicted because only SSE teardown drives eviction and stdio never calls `closeStream`.

**User decisions (already made):** Traces to the 2026-07-02 security/perf review backlog (parent `gargantua-vh3f`), direct follow-up to `gargantua-rupy`. The issue body fixes the WHAT: closeStream teardown evicts both maps; `.stdio` untouched; test proves reused/fresh session cannot resolve the old session's item_ids.

---

### Task 1: Evict per-connection MCP state on SSE stream teardown

**Goal:** SSE stream close drops the connection's scan-session cache and client identity; stdio is untouched; a reused session id cannot resolve a closed session's item_ids.

**Files:**
- Modify: `Sources/GargantuaCore/Services/MCP/MCPScanSessionCacheRegistry.swift` — add `evict(_:)`, update lifecycle doc-comment
- Modify: `Sources/GargantuaCore/Services/MCP/MCPRequestDispatcher.swift` — add `evictClientIdentity(for:)`
- Modify: `Sources/GargantuaCore/Services/MCP/MCPSSERequestRouter.swift` — add `ConnectionCloseHandler` typealias + `onClose` init param; call it from `closeStream`
- Modify: `Sources/GargantuaCore/Services/MCP/MCPSSETransport.swift` — add `onConnectionClose` init param, thread to router
- Modify: `Sources/GargantuaMCP/main.swift` — wire `onConnectionClose` to evict both maps
- Test: `Tests/GargantuaCoreTests/Services/MCP/MCPConnectionTeardownEvictionTests.swift` (new)

**Acceptance Criteria:**
- [ ] `MCPScanSessionCacheRegistry.evict(_:)` removes the cache for a connection; a subsequent `cache(for:)` vends a fresh empty instance (distinct identity from the pre-evict one).
- [ ] `MCPRequestDispatcher.evictClientIdentity(for:)` removes the identity so `currentClientIdentity(for:)` returns nil.
- [ ] `MCPSSERequestRouter.closeStream(sessionID:)` invokes the `onClose` handler with `.sse(sessionID)` (after releasing the router lock).
- [ ] Closing an SSE session drops both its registry cache and its `clientIdentities` entry; a `clean` on the reused/fresh session id gets `invalidParams` "Unknown item_id" for the closed session's ids.
- [ ] `.stdio` state survives an SSE session close (its cache instance and identity are unchanged).
- [ ] Existing `MCPSSETransport(...)` / `MCPSSERequestRouter(...)` call sites compile unchanged (new params default to `nil`).

**Verify:** `swift test --filter MCPConnectionTeardownEviction` → green; `swift test --filter MCPScanSessionCachePartition` → still green (no regression).

**Steps:**

1. `MCPScanSessionCacheRegistry` — add after `cache(for:)`:
   ```swift
   /// Evicts the cache for `connection`, dropping its retained scan-result
   /// set. Called on SSE session teardown (see `MCPSSERequestRouter.closeStream`)
   /// so a long-lived SSE daemon does not accumulate orphaned per-connection
   /// caches for the process lifetime. No-op if the connection has no cache.
   /// `.stdio` is never evicted — only SSE session teardown drives eviction.
   public func evict(_ connection: MCPConnectionID) {
       lock.lock()
       defer { lock.unlock() }
       caches.removeValue(forKey: connection)
   }
   ```
   Update the "Lifecycle note" doc-comment: this eviction now closes the follow-up the note references (drop the "tracked as a follow-up" sentence, state that SSE teardown evicts).

2. `MCPRequestDispatcher` — add near `currentClientIdentity(for:)`:
   ```swift
   /// Drops the captured client identity for `connection`. Called on SSE
   /// session teardown so the per-connection `clientIdentities` map does not
   /// retain orphaned entries for the process lifetime. No-op if the
   /// connection never completed `initialize`. `.stdio` is never evicted —
   /// its single session lives for the whole process.
   public func evictClientIdentity(for connection: MCPConnectionID) {
       lock.lock()
       defer { lock.unlock() }
       clientIdentities.removeValue(forKey: connection)
   }
   ```

3. `MCPSSERequestRouter` — add the typealias, store the handler, invoke on close:
   ```swift
   /// Invoked when an SSE session tears down, so callers can evict any
   /// per-connection state keyed by the session's `MCPConnectionID`.
   public typealias ConnectionCloseHandler = @Sendable (_ connection: MCPConnectionID) -> Void
   ```
   Add stored property `private let onClose: ConnectionCloseHandler?` and an `onClose: ConnectionCloseHandler? = nil` init param (assign in `init`). Rewrite `closeStream`:
   ```swift
   public func closeStream(sessionID: String) {
       lock.lock()
       sessions.removeValue(forKey: sessionID)
       lock.unlock()
       // Fire eviction outside the router lock so the callback can take the
       // registry/dispatcher locks without nesting under ours.
       onClose?(.sse(sessionID))
   }
   ```

4. `MCPSSETransport` — add `onConnectionClose: MCPSSERequestRouter.ConnectionCloseHandler? = nil` init param (after `handler`, before `log`); pass to router:
   ```swift
   self.router = MCPSSERequestRouter(handler: handler, log: log, onClose: onConnectionClose)
   ```

5. `main.swift` — in the `MCPSSETransport(...)` construction, add:
   ```swift
   onConnectionClose: { connection in
       scanSessionCacheRegistry.evict(connection)
       dispatcher.evictClientIdentity(for: connection)
   },
   ```

6. New test file `MCPConnectionTeardownEvictionTests.swift`:
   - `registry.evict drops the cache and a fresh one is vended`: `let c1 = registry.cache(for: .sse("s1"))`; `registry.evict(.sse("s1"))`; `let c2 = registry.cache(for: .sse("s1"))`; `#expect(c1 !== c2)`; `#expect(c2.isEmpty)`.
   - `dispatcher.evictClientIdentity clears the captured identity`: dispatch `initialize` with `clientInfo.name` on `.sse("s1")`; `#expect(dispatcher.currentClientIdentity(for: .sse("s1")) != nil)`; `dispatcher.evictClientIdentity(for: .sse("s1"))`; `#expect(dispatcher.currentClientIdentity(for: .sse("s1")) == nil)`.
   - `closeStream fires onClose with the session's connection id`: build a router with `onClose` recording into a box; `router.closeStream(sessionID: "s1")`; `#expect(box.value == .sse("s1"))`.
   - `SSE teardown evicts both maps and a reused session cannot resolve the closed session's item_ids`: wire dispatcher + registry + router exactly as main.swift (scan + clean handlers via `registry.cache(for: dispatcher.currentCallConnection())`, `onClose = { registry.evict($0); dispatcher.evictClientIdentity(for: $0) }`); dispatch initialize+scan on `.sse("s1")` → item resolves; `router.closeStream(sessionID: "s1")`; assert identity gone, a fresh `cache(for: .sse("s1"))` is empty, and a `clean` with the old item_id on `.sse("s1")` returns `invalidParams`/"Unknown item_id".
   - `.stdio survives an SSE session close`: populate `.stdio` cache + identity, `router.closeStream(sessionID: "s1")`, assert `.stdio` cache instance identity unchanged and its identity still present.
   Use the partition test's `ScanResult(id: "safe-a", …)` scanner fixture and the `initialize`/`tools/call` request-building style. Recorder box mirrors `ConnectionCaptureBox` (`@unchecked Sendable` single-value).
