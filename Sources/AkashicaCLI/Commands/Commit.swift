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
        guard let workspace = try config.currentWorkspace() else {
            print("Error: Not in a workspace. Use 'akashica checkout' to create one.")
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

        // Clear workspace
        try config.clearWorkspace()

        print("[\(branch) \(newCommit.value)] \(message)")
        print("Workspace published and closed")
    }
}
