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
        // The original EPERM message survives (so the summary classifier still
        // routes to an ownership prompt) AND the helper's real reason is appended
        // so the actual failure is never hidden.
        let error = result.itemResults.first?.error
        #expect(error?.contains("Operation not permitted") == true)
        #expect(error?.contains("SMAppServiceErrorDomain error 1") == true)
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

    @Test("Root-owned Trash items are escalated as deleteFromTrash and cleared on success")
    @MainActor
    func trashFailuresEscalateAsDeleteFromTrash() async throws {
        let fixture = try makeFakeTrash(children: ["stuck.app": Data("x".utf8)])
        let fm = FileManager.default
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.trash.path)
            try? fm.removeItem(at: fixture.home)
        }
        // Make the Trash directory read-only so removeItem on its child fails
        // with a permission error, standing in for a root-owned item.
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.trash.path)

        let helper = StubPrivilegedHelper(mode: .succeedAll)
        let engine = CleanupEngine(
            homeDirectoryForTesting: fixture.home,
            privilegedHelper: helper
        )
        let trashItem = makeItem(id: "trash", path: fixture.trash.path)

        let result = await engine.clean([trashItem], method: .delete)

        #expect(helper.received.count == 1)
        #expect(helper.received.first?.items.first?.operation == .deleteFromTrash)
        #expect(helper.received.first?.invokingUserID == getuid())
        // The stub reports the child removed, so the aggregate Trash result clears.
        #expect(result.allSucceeded)
    }

    @Test("deleteFromTrash operation round-trips through Codable")
    func deleteFromTrashOperationCodable() throws {
        let item = PrivilegedUninstallItem(
            id: "x", path: "/Users/x/.Trash/y", category: "other", size: 0,
            operation: .deleteFromTrash
        )
        let data = try PrivilegedUninstallXPCCodec.encoder.encode(item)
        let decoded = try PrivilegedUninstallXPCCodec.decoder.decode(PrivilegedUninstallItem.self, from: data)
        #expect(decoded.operation == .deleteFromTrash)
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
