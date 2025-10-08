import ArgumentParser
import Foundation
import Akashica

struct Commit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Record changes to the repository"
    )

    @Option(name: .long, help: "Profile name (defaults to AKASHICA_PROFILE environment variable)")
    var profile: String?

    @Option(name: .shortAndLong, help: "Commit message")
    var message: String

    @Option(name: .long, help: "Branch to commit to")
    var branch: String = "main"

    func run() async throws {
        var context = try await CommandContext.resolve(profileFlag: profile)

        // Check if in view mode
        if context.workspace.view.active {
            print("Error: Cannot commit in view mode")
            print("Exit view mode first: akashica view --exit")
            throw ExitCode.failure
        }

        // Get workspace ID
        let workspace = try context.currentWorkspaceID()

        // Get author name
        let author = ProcessInfo.processInfo.environment["USER"] ?? "unknown"

        // Publish workspace
        let newCommit = try await context.repository.publishWorkspace(
            workspace,
            toBranch: branch,
            message: message,
            author: author
        )

        // After commit, old workspace is deleted - create new workspace from new commit
        let newWorkspace = try await context.repository.createWorkspace(from: newCommit)
        try await context.updateWorkspace { state in
            state.workspaceId = newWorkspace.fullReference
            state.baseCommit = newCommit.value
        }

        print("[\(branch) \(newCommit.value)] \(message)")
        print("Workspace published. New workspace: \(newWorkspace.fullReference)")
    }
}
