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

    @Option(name: .long, help: "Profile name (defaults to AKASHICA_PROFILE environment variable)")
    var profile: String?

    func run() async throws {
        let context = try await CommandContext.resolve(profileFlag: profile)

        // Check if in view mode
        if context.workspace.view.active {
            print("Error: Cannot show status in view mode")
            print("Exit view mode first: akashica view --exit")
            throw ExitCode.failure
        }

        let workspace = try context.currentWorkspaceID()
        let session = await context.repository.session(workspace: workspace)
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
