import Combine
import Foundation
import os
import Testing
@testable import GargantuaCore

@Suite("MCPServerStatusViewModel")
@MainActor
struct MCPServerStatusViewModelTests {
    @Test("refresh skips the published assignment when nothing observable changed")
    func refreshSuppressesRedundantPublish() {
        let providerState = OSAllocatedUnfairLock(initialState: MCPServerRunState.running)
        let model = MCPServerStatusViewModel(
            snapshotProvider: {
                // Fresh updatedAt on every read, like readSnapshot() produces.
                MCPServerStatusSnapshot(state: providerState.withLock { $0 }, updatedAt: Date())
            },
            startAction: { .stopped() },
            stopAction: { .stopped() },
            auditReader: { [] }
        )

        var fires = 0
        let subscription = model.objectWillChange.sink { fires += 1 }
        defer { subscription.cancel() }

        model.refresh()
        model.refresh()
        #expect(fires == 0)

        providerState.withLock { $0 = .stopped }
        model.refresh()
        #expect(fires == 1)
        #expect(model.snapshot.state == .stopped)
    }

    @Test("refresh publishes a persistent provider error only once")
    func refreshSuppressesRepeatedErrorPublish() {
        struct ProviderError: Error {}
        let model = MCPServerStatusViewModel(
            snapshotProvider: { throw ProviderError() },
            startAction: { .stopped() },
            stopAction: { .stopped() },
            auditReader: { [] }
        )
        #expect(model.snapshot.state == .error)

        var fires = 0
        let subscription = model.objectWillChange.sink { fires += 1 }
        defer { subscription.cancel() }

        model.refresh()
        model.refresh()
        #expect(fires == 0)
    }
}
