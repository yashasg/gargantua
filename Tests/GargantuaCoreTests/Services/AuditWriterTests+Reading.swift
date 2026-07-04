import Foundation
import Testing
@testable import GargantuaCore

extension AuditWriterTests {
    @Test("readEntries returns all written entries")
    func readEntries() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let writer = AuditWriter(logDirectory: dir)

        for i in 1 ... 3 {
            let entry = AuditEntry(
                tool: "native",
                command: "clean",
                files: [AuditFile(path: "/tmp/file\(i).txt", size: Int64(i * 100))],
                safetyLevel: .safe,
                confirmationMethod: .singleButton,
                bytesFreed: Int64(i * 100)
            )
            try writer.write(entry)
        }

        let entries = try writer.readEntries()
        #expect(entries.count == 3)
        #expect(entries[0].files[0].path == "/tmp/file1.txt")
        #expect(entries[2].files[0].path == "/tmp/file3.txt")
    }

    @Test("readEntries returns empty array for nonexistent log")
    func readEntriesNoFile() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let writer = AuditWriter(logDirectory: dir.appendingPathComponent("nope"))
        let entries = try writer.readEntries()
        #expect(entries.isEmpty)
    }

    @Test("readEntries reflects entries appended after a cached read")
    func readEntriesCacheInvalidatesOnAppend() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let writer = AuditWriter(logDirectory: dir)
        try writer.write(makeReadEntry(path: "/tmp/first.txt"))
        #expect(try writer.readEntries().count == 1)

        try writer.write(makeReadEntry(path: "/tmp/second.txt"))
        let entries = try writer.readEntries()
        #expect(entries.count == 2)
        #expect(entries.last?.files.first?.path == "/tmp/second.txt")
    }

    @Test("readEntries serves the cached decode while mtime and size are unchanged")
    func readEntriesUsesCache() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let writer = AuditWriter(logDirectory: dir)
        try writer.write(makeReadEntry(path: "/tmp/original.txt"))

        // Pin mtime to a whole second so setting it again after the rewrite
        // lands on the identical stat timestamp (sub-second Dates don't
        // round-trip exactly through setAttributes).
        let pinnedDate = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: pinnedDate],
            ofItemAtPath: writer.logFile.path
        )
        #expect(try writer.readEntries().count == 1)

        // Corrupt the file without changing its mtime or size. A cached
        // reader keeps returning the prior decode; an uncached one would
        // decode garbage and return nothing.
        let attributes = try FileManager.default.attributesOfItem(atPath: writer.logFile.path)
        let size = try #require(attributes[.size] as? NSNumber).intValue
        try Data(repeating: UInt8(ascii: "x"), count: size).write(to: writer.logFile)
        try FileManager.default.setAttributes(
            [.modificationDate: pinnedDate],
            ofItemAtPath: writer.logFile.path
        )

        let entries = try writer.readEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.files.first?.path == "/tmp/original.txt")
    }

    private func makeReadEntry(path: String) -> AuditEntry {
        AuditEntry(
            tool: "native",
            command: "clean",
            files: [AuditFile(path: path, size: 100)],
            safetyLevel: .safe,
            confirmationMethod: .singleButton,
            bytesFreed: 100
        )
    }
}
