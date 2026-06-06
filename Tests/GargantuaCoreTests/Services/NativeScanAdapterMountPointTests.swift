import Foundation
import Testing
@testable import GargantuaCore

@Suite("NativeScanAdapter mount-point guard")
struct NativeScanAdapterMountPointTests {
    @Test("A same-volume directory is not a mount point")
    func sameVolumeDirIsNotMount() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mnt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(NativeScanAdapter.isMountPoint(dir.path) == false)
    }

    @Test("A separate volume is a mount point")
    func separateVolumeIsMount() {
        // /dev is a devfs mount on every macOS system — a different device than /.
        #expect(NativeScanAdapter.isMountPoint("/dev") == true)
    }

    @Test("A missing path is not treated as a mount point")
    func missingPathIsNotMount() {
        #expect(NativeScanAdapter.isMountPoint("/no/such/path/\(UUID().uuidString)") == false)
    }
}
