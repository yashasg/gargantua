import Foundation
import Testing
@testable import GargantuaCore

@Suite("ProcessSpawner child environment")
struct ProcessSpawnerEnvironmentTests {

    @Test("prepends the executable's directory to PATH")
    func prependsBinDir() {
        // A directory that won't already be on the test host's PATH, so the
        // dedup branch can't mask the prepend.
        let env = ProcessSpawner.childEnvironment(
            for: URL(fileURLWithPath: "/var/empty/gargantua-fake-bin/pnpm")
        )
        let path = env["PATH"] ?? ""
        #expect(path.hasPrefix("/var/empty/gargantua-fake-bin:"))
    }

    @Test("does not duplicate a directory already on PATH")
    func noDuplicate() {
        // Whatever the current process PATH is, re-resolving a binary that
        // lives in one of its segments must not prepend a second copy.
        let existing = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let firstSegment = existing.split(separator: ":").first.map(String.init) ?? "/usr/bin"
        let env = ProcessSpawner.childEnvironment(
            for: URL(fileURLWithPath: "\(firstSegment)/sometool")
        )
        #expect(env["PATH"] == existing)
    }

    @Test("end-to-end: a node-shim-style sibling resolves via env")
    func siblingResolvesViaEnv() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("gargantua-spawn-\(getpid())")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // `helper` stands in for `node`: reachable only via PATH.
        let helper = dir.appendingPathComponent("helper")
        try "#!/bin/sh\necho resolved\n".write(to: helper, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        // `tool` stands in for the `pnpm` shim: run by absolute path, but it
        // re-execs its sibling through `env`, which searches PATH.
        let tool = dir.appendingPathComponent("tool")
        try "#!/bin/sh\nexec env helper\n".write(to: tool, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        let output = try DefaultProcessRunner().run(executable: tool, arguments: [])
        #expect(output.exitCode == 0)
        #expect(output.stdout == "resolved\n")
    }
}
