import ArgumentParser
import Foundation
import Akashica

struct Commit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Record changes to the repository"
    )

    @OptionGroup var storage: StorageOptions

    @Option(name: .shortAndLong, help: "Commit message")
    var message: String

    @Option(name: .long, help: "Branch to commit to")
    var branch: String = "main"

    func run() async throws {
        let config = storage.makeConfig()

        // Create validated repository (efficient - one S3 adapter creation)
        let repo = try await config.createValidatedRepository()

        // Get current workspace
        let workspaceFile = config.akashicaPath.appendingPathComponent("WORKSPACE")
        guard FileManager.default.fileExists(atPath: workspaceFile.path) else {
            print("Error: Not in a workspace")
            throw ExitCode.failure
        }

        let workspaceRef = try String(contentsOf: workspaceFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let workspace = parseWorkspaceID(workspaceRef) else {
            print("Error: Invalid workspace reference")
            throw ExitCode.failure
        }

        // Get author name
        let author = ProcessInfo.processInfo.environment["USER"] ?? "unknown"

        // Publish workspace
        let newCommit = try await repo.publishWorkspace(
            workspace,
            toBranch: branch,
            message: message,
            author: author
        )

        // Clear workspace file
        try? FileManager.default.removeItem(at: workspaceFile)

        print("[\(branch) \(newCommit.value)] \(message)")
    }

    private func parseWorkspaceID(_ ref: String) -> WorkspaceID? {
        let parts = ref.split(separator: "$")
        guard parts.count == 2 else { return nil }

        let baseCommit = CommitID(value: String(parts[0]))
        let suffix = String(parts[1])

        return WorkspaceID(baseCommit: baseCommit, workspaceSuffix: suffix)
    }
}
