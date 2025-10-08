import ArgumentParser
import Foundation
import Akashica
import AkashicaStorage

struct Checkout: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new workspace from a branch or commit"
    )

    @Option(name: .long, help: "Profile name (defaults to AKASHICA_PROFILE environment variable)")
    var profile: String?

    @Argument(help: "Branch name or commit ID (e.g., 'main' or '@1001')")
    var ref: String

    func run() async throws {
        var context = try await CommandContext.resolve(profileFlag: profile)

        // Exit view mode if active
        if context.workspace.view.active {
            try await context.exitView()
            print("Exited view mode")
        }

        // Parse reference (branch or commit)
        let refType = RefType.parse(ref)

        let workspace: WorkspaceID
        let baseCommit: CommitID

        switch refType {
        case .commit(let commitID):
            // Checkout from commit ID
            workspace = try await context.repository.createWorkspace(from: commitID)
            baseCommit = commitID

        case .branch(let branchName):
            // Checkout from branch
            do {
                workspace = try await context.repository.createWorkspace(fromBranch: branchName)
                // Get base commit from workspace ID
                baseCommit = workspace.baseCommit
            } catch {
                print("Error: Branch '\(branchName)' not found")
                print("Use 'akashica branch' to see available branches")
                throw ExitCode.failure
            }
        }

        // Update workspace state with new workspace
        try await context.updateWorkspace { state in
            state.workspaceId = workspace.fullReference
            state.baseCommit = baseCommit.value
            state.virtualCwd = "/"  // Reset to root
        }

        switch refType {
        case .commit:
            print("Created workspace \(workspace.fullReference) from commit \(ref)")
        case .branch(let branchName):
            print("Created workspace \(workspace.fullReference) from branch '\(branchName)'")
            print("Base commit: \(baseCommit.value)")
        }
        print("Virtual CWD: /")
    }
}
