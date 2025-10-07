import ArgumentParser
import Foundation
import Akashica

struct Cd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Change virtual working directory"
    )

    @OptionGroup var storage: StorageOptions

    @Argument(help: "Directory path")
    var path: String

    func run() async throws {
        let config = storage.makeConfig()

        // Get current workspace
        guard let workspace = try config.currentWorkspace() else {
            print("Error: Not in a workspace. Use 'akashica checkout' to create one.")
            throw ExitCode.failure
        }

        // Create session
        let repo = try await config.createValidatedRepository()
        let session = await repo.session(workspace: workspace)

        // Resolve path (relative to virtual CWD)
        let vctx = config.virtualContext()
        let targetPath = vctx.resolvePath(path)

        // Verify directory exists
        do {
            let entries = try await session.listDirectory(at: targetPath)
            _ = entries // Just to verify it's a directory

            // Update virtual CWD
            try vctx.changeDirectory(to: targetPath)

            // Print new path
            print(targetPath.pathString.isEmpty ? "/" : targetPath.pathString)
        } catch AkashicaError.fileNotFound {
            print("Error: Directory not found: \(targetPath.pathString)")
            throw ExitCode.failure
        }
    }
}
