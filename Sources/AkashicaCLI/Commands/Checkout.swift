import ArgumentParser
import Foundation
import Akashica
import AkashicaStorage

struct Checkout: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a new workspace from a branch or commit"
    )

    @OptionGroup var storage: StorageOptions

    @Argument(help: "Branch name or commit ID (e.g., 'main' or '@1001')")
    var ref: String

    func run() async throws {
        let config = storage.makeConfig()

        // Create validated storage (efficient - one S3 adapter creation)
        let storageAdapter = try await config.createValidatedStorage()
        let repo = AkashicaRepository(storage: storageAdapter)

        // Parse reference (branch or commit)
        let refType = RefType.parse(ref)

        let workspace: WorkspaceID
        let baseCommit: CommitID

        switch refType {
        case .commit(let commitID):
            // Checkout from commit ID
            // Verify commit exists
            do {
                _ = try await storageAdapter.readCommitMetadata(commit: commitID)
            } catch {
                print("Error: Commit '\(ref)' not found")
                throw ExitCode.failure
            }

            workspace = try await repo.createWorkspace(from: commitID)
            baseCommit = commitID

        case .branch(let branchName):
            // Checkout from branch
            do {
                workspace = try await repo.createWorkspace(fromBranch: branchName)
                let pointer = try await storageAdapter.readBranch(name: branchName)
                baseCommit = pointer.head
            } catch {
                print("Error: Branch '\(branchName)' not found")
                print("Use 'akashica branch' to see available branches")
                throw ExitCode.failure
            }
        }

        // Save workspace reference
        // Ensure .akashica directory exists (for both local and S3 modes)
        if !FileManager.default.fileExists(atPath: config.akashicaPath.path) {
            try FileManager.default.createDirectory(
                at: config.akashicaPath,
                withIntermediateDirectories: true
            )
        }

        let workspaceFile = config.akashicaPath.appendingPathComponent("WORKSPACE")
        try workspace.fullReference.write(to: workspaceFile, atomically: true, encoding: .utf8)

        switch refType {
        case .commit:
            print("Created workspace \(workspace.fullReference) from commit \(ref)")
        case .branch(let branchName):
            print("Created workspace \(workspace.fullReference) from branch '\(branchName)'")
            print("Base commit: \(baseCommit.value)")
        }
    }
}
