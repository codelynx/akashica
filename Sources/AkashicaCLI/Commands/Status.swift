import ArgumentParser
import Foundation
import Akashica

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show the working tree status",
        discussion: """
        Shows which files have been added, modified, or deleted in the current workspace.

        Example:
          akashica status

        Note: Only works with current workspace. Shows changes compared to base commit.
        """
    )

    @OptionGroup var storage: StorageOptions

    func run() async throws {
        let config = storage.makeConfig()

        // Create validated repository (efficient - one S3 adapter creation)
        let repo = try await config.createValidatedRepository()

        // Get current workspace
        guard let workspace = try config.currentWorkspace() else {
            print("Not in a workspace. Use 'akashica checkout' to create one.")
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
}
