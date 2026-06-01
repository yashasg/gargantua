import Testing
import Foundation
@testable import GargantuaCore

/// Drives `ClaudeCodeOrganizerProposer.propose` end-to-end through a fake
/// `claude` CLI (a shell script) so the subprocess round-trip, exit-code
/// mapping, timeout, and response parsing are all exercised hermetically.
@Suite("ClaudeCodeOrganizerProposer")
struct ClaudeCodeOrganizerProposerTests {

    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// Builds a proposer whose CLI is a generated script. When `enabled` is
    /// false the config is saved disabled and no script is written.
    private func makeProposer(
        enabled: Bool,
        cliBody: String = "",
        timeoutSeconds: Int = 240
    ) throws -> ClaudeCodeOrganizerProposer {
        let store = ClaudeCodeAgentConfigurationStore(defaults: OrganizerProposerTestSupport.makeDefaults())
        let cliPath = enabled
            ? try OrganizerProposerTestSupport.writeExecutableScript(cliBody).path
            : ""
        store.save(ClaudeCodeAgentConfiguration(
            isEnabled: enabled,
            cliPath: cliPath,
            selectedModel: "test-model"
        ))
        let captured = fixedDate
        return ClaudeCodeOrganizerProposer(
            configurationStore: store,
            now: { captured },
            timeoutSeconds: timeoutSeconds
        )
    }

    // MARK: - Guard

    @Test("Disabled agent throws agentNotEnabled before touching the CLI")
    func disabledThrows() async throws {
        let proposer = try makeProposer(enabled: false)
        let folder = try OrganizerProposerTestSupport.makeSourceFolder(files: ["a.pdf", "b.pdf"])
        defer { try? FileManager.default.removeItem(at: folder) }

        await #expect(throws: ClaudeCodeOrganizerError.agentNotEnabled) {
            _ = try await proposer.propose(sourceFolder: folder)
        }
    }

    // MARK: - Happy path

    @Test("Valid CLI response round-trips into an OrganizationProposal")
    func happyPath() async throws {
        let json = #"{"plans":[{"cluster_id":"C1","name":"Receipts","reasoning":"PDFs"}]}"#
        let proposer = try makeProposer(enabled: true, cliBody: "printf '%s' '\(json)'\n")
        let folder = try OrganizerProposerTestSupport.makeSourceFolder(files: ["alpha.pdf", "beta.pdf"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let proposal = try await proposer.propose(sourceFolder: folder)

        #expect(proposal.backend == .cloud)
        #expect(proposal.generatedAt == fixedDate)
        #expect(proposal.sourceFolder == folder)
        #expect(proposal.plans.count == 1)
        #expect(proposal.plans.first?.name == "Receipts")
        #expect(proposal.plans.first?.moves.count == 2)
        #expect(proposal.plans.first?.moves.map(\.sourceURL.lastPathComponent).sorted() == ["alpha.pdf", "beta.pdf"])
    }

    // MARK: - Failure mapping

    @Test("Non-zero CLI exit maps to cliFailed with the exit code and stderr")
    func cliFailureThrows() async throws {
        let proposer = try makeProposer(enabled: true, cliBody: "echo 'boom' 1>&2\nexit 3\n")
        let folder = try OrganizerProposerTestSupport.makeSourceFolder(files: ["a.pdf", "b.pdf"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let error = await #expect(throws: ClaudeCodeOrganizerError.self) {
            _ = try await proposer.propose(sourceFolder: folder)
        }
        guard case .cliFailed(let exitCode, let stderr) = error else {
            Issue.record("expected .cliFailed, got \(String(describing: error))")
            return
        }
        #expect(exitCode == 3)
        #expect(stderr.contains("boom"))
    }

    @Test("Exit 0 with no stdout maps to emptyResponse")
    func emptyOutputThrows() async throws {
        let proposer = try makeProposer(enabled: true, cliBody: "exit 0\n")
        let folder = try OrganizerProposerTestSupport.makeSourceFolder(files: ["a.pdf", "b.pdf"])
        defer { try? FileManager.default.removeItem(at: folder) }

        await #expect(throws: ClaudeCodeOrganizerError.emptyResponse) {
            _ = try await proposer.propose(sourceFolder: folder)
        }
    }

    @Test("A CLI that never returns is terminated and maps to timedOut")
    func timeoutThrows() async throws {
        // sleep far longer than any plausible scheduling delay so the only
        // exit path is the timeout watcher firing — under parallel CI load a
        // short sleep can finish naturally before a delayed watcher wakes.
        let proposer = try makeProposer(enabled: true, cliBody: "sleep 600\n", timeoutSeconds: 1)
        let folder = try OrganizerProposerTestSupport.makeSourceFolder(files: ["a.pdf", "b.pdf"])
        defer { try? FileManager.default.removeItem(at: folder) }

        await #expect(throws: ClaudeCodeOrganizerError.timedOut(seconds: 1)) {
            _ = try await proposer.propose(sourceFolder: folder)
        }
    }

    // MARK: - Error copy

    @Test("Error descriptions are user-facing and stable")
    func errorDescriptions() {
        #expect(ClaudeCodeOrganizerError.agentNotEnabled.errorDescription?.contains("Settings") == true)
        #expect(ClaudeCodeOrganizerError.emptyResponse.errorDescription?.contains("no output") == true)
        #expect(ClaudeCodeOrganizerError.timedOut(seconds: 5).errorDescription?.contains("5s") == true)
        #expect(
            ClaudeCodeOrganizerError.cliFailed(exitCode: 2, stderr: "   ").errorDescription
                == "claude CLI exited with status 2."
        )
        #expect(
            ClaudeCodeOrganizerError.cliFailed(exitCode: 2, stderr: "nope").errorDescription
                == "claude CLI failed: nope"
        )
    }
}
