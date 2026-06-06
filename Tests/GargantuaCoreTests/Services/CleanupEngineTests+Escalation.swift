import Foundation
import Testing
@testable import GargantuaCore

@MainActor
final class StubPrivilegedHelper: PrivilegedUninstallHelping {
    enum Mode {
        case succeedAll
        case failAll(String)
    }

    private let mode: Mode
    private(set) var received: [PrivilegedUninstallRequest] = []

    init(mode: Mode) { self.mode = mode }

    func movePrivilegedItemsToTrash(
        _ request: PrivilegedUninstallRequest,
        authorization: UninstallAuthorization
    ) async -> [CleanupItemResult] {
        received.append(request)
        return request.items.map { item in
            let scan = ScanResult(
                id: item.id,
                name: URL(fileURLWithPath: item.path).lastPathComponent,
                path: item.path,
                size: item.size,
                safety: .protected_,
                confidence: 100,
                explanation: "privileged",
                source: SourceAttribution(name: "Test"),
                category: item.category
            )
            switch mode {
            case .succeedAll:
                return CleanupItemResult(
                    item: scan,
                    succeeded: true,
                    trashURL: URL(fileURLWithPath: "/Users/test/.Trash/\(scan.name)")
                )
            case .failAll(let message):
                return CleanupItemResult(item: scan, succeeded: false, error: message)
            }
        }
    }
}

extension CleanupResultTests {
    @Test("Permission-class trash failures are escalated through the privileged helper")
    @MainActor
    func permissionFailureEscalatesToPrivilegedHelper() async {
        let item = makeItem(id: "root-owned", path: "/tmp/gargantua-root-owned", size: 4096)
        let mover = RecordingTrashMover(outcome: .failure("Operation not permitted"))
        let helper = StubPrivilegedHelper(mode: .succeedAll)
        let engine = CleanupEngine(
            homeDirectoryForTesting: FileManager.default.homeDirectoryForCurrentUser,
            trashMover: mover,
            privilegedHelper: helper
        )

        let result = await engine.clean([item], method: .trash)

        #expect(helper.received.count == 1)
        #expect(helper.received.first?.items.first?.id == "root-owned")
        #expect(result.allSucceeded)
        #expect(result.totalFreed == 4096)
        #expect(result.itemResults.first?.trashURL != nil)
    }

    @Test("Escalation that also fails keeps the original ownership error, not the helper's XPC noise")
    @MainActor
    func escalationFailurePreservesOriginalError() async {
        let item = makeItem(id: "root-owned", path: "/tmp/gargantua-root-owned", size: 4096)
        let mover = RecordingTrashMover(outcome: .failure("Operation not permitted"))
        let helper = StubPrivilegedHelper(mode: .failAll("SMAppServiceErrorDomain error 1"))
        let engine = CleanupEngine(
            homeDirectoryForTesting: FileManager.default.homeDirectoryForCurrentUser,
            trashMover: mover,
            privilegedHelper: helper
        )

        let result = await engine.clean([item], method: .trash)

        #expect(helper.received.count == 1)
        #expect(result.failedItems.count == 1)
        // The original EPERM message survives so the summary classifier still
        // routes to an ownership remediation prompt.
        #expect(result.itemResults.first?.error == "Operation not permitted")
    }

    @Test("Non-permission failures are not escalated")
    @MainActor
    func nonPermissionFailureSkipsEscalation() async {
        let item = makeItem(id: "missing", path: "/tmp/gargantua-missing", size: 10)
        let mover = RecordingTrashMover(outcome: .failure("No such file or directory"))
        let helper = StubPrivilegedHelper(mode: .succeedAll)
        let engine = CleanupEngine(
            homeDirectoryForTesting: FileManager.default.homeDirectoryForCurrentUser,
            trashMover: mover,
            privilegedHelper: helper
        )

        let result = await engine.clean([item], method: .trash)

        #expect(helper.received.isEmpty)
        #expect(result.failedItems.count == 1)
    }

    @Test("Without a privileged helper, permission failures stay failed")
    @MainActor
    func permissionFailureWithoutHelperStaysFailed() async {
        let item = makeItem(id: "root-owned", path: "/tmp/gargantua-root-owned", size: 4096)
        let mover = RecordingTrashMover(outcome: .failure("Operation not permitted"))
        let engine = CleanupEngine(
            homeDirectoryForTesting: FileManager.default.homeDirectoryForCurrentUser,
            trashMover: mover
        )

        let result = await engine.clean([item], method: .trash)

        #expect(result.failedItems.count == 1)
    }
}
