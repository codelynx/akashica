import ArgumentParser
import Foundation
import Akashica
import AkashicaStorage

struct View: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Enter read-only view mode at a specific commit"
    )

    @OptionGroup var storage: StorageOptions

    @Argument(help: "Commit ID to view (e.g., '@1020')")
    var commitID: String?

    @Flag(name: .long, help: "Exit view mode and return to workspace")
    var exit: Bool = false

    func run() async throws {
        let config = storage.makeConfig()

        // Handle --exit flag
        if exit {
            try exitViewMode(config: config)
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

        // Create validated storage
        let storageAdapter = try await config.createValidatedStorage()

        // Verify commit exists
        do {
            _ = try await storageAdapter.readCommitMetadata(commit: commit)
        } catch {
            print("Error: Commit '\(commitID)' not found")
            throw ExitCode.failure
        }

        // Ensure .akashica directory exists
        if !FileManager.default.fileExists(atPath: config.akashicaPath.path) {
            try FileManager.default.createDirectory(
                at: config.akashicaPath,
                withIntermediateDirectories: true
            )
        }

        // Save view reference
        try config.saveView(commit)

        // Clear workspace if any (view mode is exclusive)
        if try config.currentWorkspace() != nil {
            try config.clearWorkspace()
        }

        // Initialize virtual CWD to root
        let vctx = config.virtualContext()
        try vctx.initialize()

        print("Entered read-only view mode at \(commitID)")
        print("Virtual CWD: /")
        print("")
        print("All commands now operate in this view context.")
        print("To exit view mode: akashica view --exit")
    }

    private func exitViewMode(config: Config) throws {
        guard config.currentView() != nil else {
            print("Not in view mode")
            return
        }

        try config.clearView()
        print("Exited view mode")
        print("")
        print("Run 'akashica checkout <branch>' to create a workspace")
    }
}
