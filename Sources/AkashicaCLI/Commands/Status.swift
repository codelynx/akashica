import ArgumentParser
import Foundation
import Akashica

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the working tree status"
    )

    @OptionGroup var storage: StorageOptions

    func run() async throws {
        let config = storage.makeConfig()

        // Create validated repository (efficient - one S3 adapter creation)
        let repo = try await config.createValidatedRepository()

        // Try to find current workspace from .akashica/WORKSPACE file
        let workspaceFile = config.akashicaPath.appendingPathComponent("WORKSPACE")

        guard FileManager.default.fileExists(atPath: workspaceFile.path) else {
            print("Not in a workspace. Use 'akashica checkout' to create one.")
            throw ExitCode.failure
        }

        let workspaceRef = try String(contentsOf: workspaceFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse workspace ID
        guard let workspace = parseWorkspaceID(workspaceRef) else {
            print("Error: Invalid workspace reference: \(workspaceRef)")
            throw ExitCode.failure
        }

        let session = await repo.session(workspace: workspace)
        let status = try await session.status()

        // Print status
        if status.added.isEmpty && status.modified.isEmpty && status.deleted.isEmpty {
            print("Nothing to commit, working tree clean")
            return
        }

        if !status.added.isEmpty {
            print("Added files:")
            for path in status.added.sorted() {
                print("  \u{001B}[32m+\u{001B}[0m \(path.pathString)")  // Green +
            }
            print("")
        }

        if !status.modified.isEmpty {
            print("Modified files:")
            for path in status.modified.sorted() {
                print("  \u{001B}[33m~\u{001B}[0m \(path.pathString)")  // Yellow ~
            }
            print("")
        }

        if !status.deleted.isEmpty {
            print("Deleted files:")
            for path in status.deleted.sorted() {
                print("  \u{001B}[31m-\u{001B}[0m \(path.pathString)")  // Red -
            }
            print("")
        }
    }

    private func parseWorkspaceID(_ ref: String) -> WorkspaceID? {
        // Format: @1001$a1b3
        let parts = ref.split(separator: "$")
        guard parts.count == 2 else { return nil }

        let baseCommit = CommitID(value: String(parts[0]))
        let suffix = String(parts[1])

        return WorkspaceID(baseCommit: baseCommit, workspaceSuffix: suffix)
    }
}
