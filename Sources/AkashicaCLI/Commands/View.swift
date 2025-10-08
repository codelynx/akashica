import ArgumentParser
import Foundation
import Akashica
import AkashicaStorage

struct View: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Enter read-only view mode at a specific commit"
    )

    @Option(name: .long, help: "Profile name (defaults to AKASHICA_PROFILE environment variable)")
    var profile: String?

    @Argument(help: "Commit ID to view (e.g., '@1020')")
    var commitID: String?

    @Flag(name: .long, help: "Exit view mode and return to workspace")
    var exit: Bool = false

    func run() async throws {
        var context = try await CommandContext.resolve(profileFlag: profile)

        // Handle --exit flag
        if exit {
            try await exitViewMode(context: &context)
            return
        }

        // Require commit ID if not exiting
        guard let commitID = commitID else {
            print("Error: Commit ID required (e.g., 'akashica view @1020')")
            print("To exit view mode: akashica view --exit")
            throw ExitCode.failure
        }

        // Parse commit ID
        guard commitID.hasPrefix("@") else {
            print("Error: Commit ID must start with '@' (e.g., '@1020')")
            throw ExitCode.failure
        }

        let commit = CommitID(value: commitID)

        // Verify commit exists by reading metadata (will throw if not found)
        do {
            _ = try await context.repository.commitMetadata(commit)
        } catch {
            print("Error: Commit '\(commitID)' not found")
            throw ExitCode.failure
        }

        // Enter view mode
        try await context.enterView(commit: commit)

        // Reset virtual CWD to root
        try await context.updateVirtualCwd(RepositoryPath(string: "/"))

        print("Entered read-only view mode at \(commitID)")
        print("Virtual CWD: /")
        print("")
        print("All commands now operate in this view context.")
        print("To exit view mode: akashica view --exit")
    }

    private func exitViewMode(context: inout CommandContext) async throws {
        guard context.workspace.view.active else {
            print("Not in view mode")
            return
        }

        try await context.exitView()
        print("Exited view mode")
        print("")
        print("Run 'akashica checkout <branch>' to create a workspace")
    }
}
