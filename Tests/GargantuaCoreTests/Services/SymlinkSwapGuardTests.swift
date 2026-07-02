import Foundation
import Testing
@testable import GargantuaCore

@Suite("SymlinkSwapGuard")
struct SymlinkSwapGuardTests {

    private func makeTempDir() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("symlink-guard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("A real file under a real directory passes")
    func realPathPasses() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("cache.bin")
        try Data("x".utf8).write(to: file)

        #expect(SymlinkSwapGuard.isUnchanged(file, scanTimeResolvedParent: nil))
    }

    @Test("A symlinked parent directory is rejected without a scan-time recording")
    func symlinkedParentRejected() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        // real/cache.bin is the scanned target; `link` is a symlink to `real`.
        let real = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: real.appendingPathComponent("cache.bin"))

        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        // Deleting through the symlinked parent must be refused.
        let throughLink = link.appendingPathComponent("cache.bin")
        #expect(!SymlinkSwapGuard.isUnchanged(throughLink, scanTimeResolvedParent: nil))
    }

    @Test("A symlink at the leaf still passes (removeItem unlinks the link, not its target)")
    func symlinkLeafPasses() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let target = dir.appendingPathComponent("target.bin")
        try Data("x".utf8).write(to: target)

        let leafLink = dir.appendingPathComponent("leaf")
        try FileManager.default.createSymbolicLink(at: leafLink, withDestinationURL: target)

        #expect(SymlinkSwapGuard.isUnchanged(leafLink, scanTimeResolvedParent: nil))
    }

    @Test("A symlink ancestor the scan already resolved through passes")
    func recordedSymlinkAncestorPasses() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        // A symlinked scan root: link -> real existed before the scan.
        let real = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: real.appendingPathComponent("cache.bin"))

        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let throughLink = link.appendingPathComponent("cache.bin")
        let recorded = throughLink.deletingLastPathComponent().resolvingSymlinksInPath().path

        #expect(SymlinkSwapGuard.isUnchanged(throughLink, scanTimeResolvedParent: recorded))
    }

    @Test("A symlink swapped to a different target after the recording is rejected")
    func swappedSymlinkRejected() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let real = root.appendingPathComponent("real", isDirectory: true)
        let victim = root.appendingPathComponent("victim", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: real.appendingPathComponent("cache.bin"))
        try Data("x".utf8).write(to: victim.appendingPathComponent("cache.bin"))

        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let throughLink = link.appendingPathComponent("cache.bin")
        let recorded = throughLink.deletingLastPathComponent().resolvingSymlinksInPath().path

        // The swap: after scan time, the link is repointed at the victim.
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim)

        #expect(!SymlinkSwapGuard.isUnchanged(throughLink, scanTimeResolvedParent: recorded))
    }
}
