import Foundation
import Testing
@testable import GargantuaCore

/// Exercises the shared one-shot runner through a real subprocess (a generated
/// shell script standing in for the `claude` CLI), so exit-code mapping, empty
/// output, and the timeout watcher are covered hermetically.
@Suite("ClaudeCodeOneShotRunner")
struct ClaudeCodeOneShotRunnerTests {

    @Test("Exit 0 with stdout returns the captured output")
    func happyPath() async throws {
        let script = try OrganizerProposerTestSupport.writeExecutableScript("printf '%s' 'hello from claude'\n")
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = ClaudeCodeOneShotRunner()

        let output = try await runner.run(executable: script, prompt: "explain", model: "")

        #expect(output == "hello from claude")
    }

    @Test("Non-zero exit maps to cliFailed with the exit code and stderr")
    func cliFailed() async throws {
        let script = try OrganizerProposerTestSupport.writeExecutableScript("printf '%s' 'boom' 1>&2\nexit 7\n")
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = ClaudeCodeOneShotRunner()

        await #expect(throws: ClaudeCodeOneShotError.cliFailed(exitCode: 7, stderr: "boom")) {
            _ = try await runner.run(executable: script, prompt: "explain", model: "")
        }
    }

    @Test("Exit 0 with no stdout maps to emptyResponse")
    func emptyResponse() async throws {
        let script = try OrganizerProposerTestSupport.writeExecutableScript("exit 0\n")
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = ClaudeCodeOneShotRunner()

        await #expect(throws: ClaudeCodeOneShotError.emptyResponse) {
            _ = try await runner.run(executable: script, prompt: "explain", model: "")
        }
    }

    @Test("A CLI that never returns in time is terminated and maps to timedOut")
    func timedOut() async throws {
        let script = try OrganizerProposerTestSupport.writeExecutableScript("sleep 30\n")
        defer { try? FileManager.default.removeItem(at: script) }
        let runner = ClaudeCodeOneShotRunner(timeoutSeconds: 1)

        await #expect(throws: ClaudeCodeOneShotError.timedOut(seconds: 1)) {
            _ = try await runner.run(executable: script, prompt: "explain", model: "")
        }
    }
}
