import Foundation
import Observation

/// View model backing the Event Horizon Console.
///
/// Receives `ScanProgressEvent`s from scanners/executors on any thread,
/// bounces to the main actor, and exposes a bounded ring buffer plus
/// aggregate stats (match count, failure count, bytes) for the view to
/// render. Call `clear()` between phases when a fresh log is desired.
@MainActor
@Observable
public final class PathStreamViewModel: ScanProgressObserving {
    /// Event log, capped at `bufferCap`. Oldest events drop first.
    public private(set) var events: [ScanProgressEvent] = []

    /// Sequence number of `events[0]`. Increments when events are dropped
    /// off the front of the ring buffer so callers that need a stable row
    /// identity can compute `firstSequence + index` and keep referring to
    /// the same event after buffer rollover.
    public private(set) var firstSequence: Int = 0

    /// Running count of `.match` outcomes since the last `clear()`.
    public private(set) var matchCount: Int = 0

    /// Running count of `.failed` outcomes since the last `clear()`.
    public private(set) var failureCount: Int = 0

    /// Running sum of `bytes` on match events, in bytes.
    public private(set) var totalBytes: Int64 = 0

    public let bufferCap: Int

    /// Nonisolated staging buffer so a scanner emitting thousands of events from
    /// a background task batches them into one main-actor hop per runloop tick
    /// instead of scheduling one `Task` per event.
    private let pending = PendingEvents()

    public nonisolated init(bufferCap: Int = 200) {
        self.bufferCap = bufferCap
    }

    public nonisolated func didEmit(_ event: ScanProgressEvent) {
        // Only the pass that transitions the buffer from idle schedules a flush;
        // events emitted before it runs ride along in the same drain, preserving
        // order and completeness.
        guard pending.stage(event) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            for event in self.pending.drain() {
                self.append(event)
            }
        }
    }

    /// Thread-safe FIFO staging area that also tracks whether a flush is already
    /// scheduled, so bursts collapse to a single main-actor drain.
    private final class PendingEvents: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer: [ScanProgressEvent] = []
        private var flushScheduled = false

        /// Appends `event`; returns `true` when the caller should schedule a
        /// flush (the buffer was idle), `false` when one is already pending.
        func stage(_ event: ScanProgressEvent) -> Bool {
            lock.lock(); defer { lock.unlock() }
            buffer.append(event)
            if flushScheduled { return false }
            flushScheduled = true
            return true
        }

        /// Returns the staged events in order and re-arms the scheduler.
        func drain() -> [ScanProgressEvent] {
            lock.lock(); defer { lock.unlock() }
            let drained = buffer
            buffer.removeAll(keepingCapacity: true)
            flushScheduled = false
            return drained
        }
    }

    /// Main-actor append used directly from tests and internal callers.
    public func append(_ event: ScanProgressEvent) {
        events.append(event)
        if events.count > bufferCap {
            let dropped = events.count - bufferCap
            events.removeFirst(dropped)
            firstSequence += dropped
        }
        switch event.outcome {
        case .match:
            matchCount += 1
            totalBytes += event.bytes ?? 0
        case .failed:
            failureCount += 1
        case .checked, .skipped:
            break
        }
    }

    /// Reset the buffer and all aggregate counters. The sequence counter is
    /// preserved across clears so IDs never collide with previously-swallowed
    /// events that a view might still remember.
    public func clear() {
        firstSequence += events.count
        events = []
        matchCount = 0
        failureCount = 0
        totalBytes = 0
    }
}
