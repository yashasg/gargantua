import Testing
import Foundation
@testable import GargantuaCore

/// Drives `CodexOrganizerProposer.propose` end-to-end through a fake `codex`
/// CLI. Unlike the Claude path, Codex reads the assistant's final reply from
/// the `-o <file>` last-message file, so the happy-path script parses its own
/// arguments and writes the canned JSON there.
@Suite("CodexOrganizerProposer")
struct CodexOrganizerProposerTests {

    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeProposer(
        enabled: Bool,
        cliBody: String = "",
        timeoutSeconds: Int = 240
    ) throws -> CodexOrganizerProposer {
        let store = CodexAgentConfigurationStore(defaults: OrganizerProposerTestSupport.makeDefaults())
        let cliPath = enabled
            ? try OrganizerProposerTestSupport.writeExecutableScript(cliBody).path
            : ""
        store.save(CodexAgentConfiguration(
            isEnabled: enabled,
            cliPath: cliPath,
            selectedModel: "test-model"
        ))
        let captured = fixedDate
        return CodexOrganizerProposer(
            configurationStore: store,
            now: { captured },
            timeoutSeconds: timeoutSeconds
        )
    }

    /// Shell that writes `json` to the path following `-o` in its arguments.
    private func writeToOutputFileScript(json: String) -> String {
        """
        out=""
        prev=""
        for a in "$@"; do
          if [ "$prev" = "-o" ]; then out="$a"; fi
          prev="$a"
        done
        printf '%s' '\(json)' > "$out"
        """
    }

    // MARK: - Guard

    @Test("Disabled agent throws CodexAgentError.disabled before touching the CLI")
    func disabledThrows() async throws {
        let proposer = try makeProposer(enabled: false)
        let folder = try OrganizerProposerTestSupport.makeSourceFolder(files: ["a.pdf", "b.pdf"])
        defer { try? FileManager.default.removeItem(at: folder) }

        await #expect(throws: CodexAgentError.disabled) {
            _ = try await proposer.propose(sourceFolder: folder)
        }
    }

    // MARK: - Happy path

    @Test("Last-message file is read and reassembled into an OrganizationProposal")
    func happyPath() async throws {
        let json = #"{"plans":[{"cluster_id":"C1","name":"Receipts","reasoning":"PDFs"}]}"#
        let proposer = try makeProposer(enabled: true, cliBody: writeToOutputFileScript(json: json))
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
        let proposer = try makeProposer(enabled: true, cliBody: "echo 'kaboom' 1>&2\nexit 7\n")
        let folder = try OrganizerProposerTestSupport.makeSourceFolder(files: ["a.pdf", "b.pdf"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let error = await #expect(throws: CodexOrganizerError.self) {
            _ = try await proposer.propose(sourceFolder: folder)
        }
        guard case .cliFailed(let exitCode, let stderr) = error else {
            Issue.record("expected .cliFailed, got \(String(describing: error))")
            return
        }
        #expect(exitCode == 7)
        #expect(stderr.contains("kaboom"))
    }

    @Test("Exit 0 without writing the last-message file maps to emptyResponse")
    func emptyOutputThrows() async throws {
        // Exits cleanly but never writes the -o file.
        let proposer = try makeProposer(enabled: true, cliBody: "exit 0\n")
        let folder = try OrganizerProposerTestSupport.makeSourceFolder(files: ["a.pdf", "b.pdf"])
        defer { try? FileManager.default.removeItem(at: folder) }

        await #expect(throws: CodexOrganizerError.emptyResponse) {
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

        await #expect(throws: CodexOrganizerError.timedOut(seconds: 1)) {
            _ = try await proposer.propose(sourceFolder: folder)
        }
    }

    // MARK: - Error copy

    @Test("Error descriptions are user-facing and stable")
    func errorDescriptions() {
        #expect(CodexOrganizerError.emptyResponse.errorDescription?.contains("codex login") == true)
        #expect(CodexOrganizerError.timedOut(seconds: 9).errorDescription?.contains("9s") == true)
        #expect(
            CodexOrganizerError.cliFailed(exitCode: 4, stderr: "  ").errorDescription
                == "codex CLI exited with status 4."
        )
        #expect(
            CodexOrganizerError.cliFailed(exitCode: 4, stderr: "bad").errorDescription
                == "codex CLI failed: bad"
        )
    }
}
