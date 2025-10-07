import ArgumentParser
import Foundation
import Akashica

struct Rm: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove file from virtual filesystem"
    )

    @OptionGroup var storage: StorageOptions

    @Argument(help: "File path to remove")
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

        // Delete file
        do {
            try await session.deleteFile(at: targetPath)
            print("Removed \(targetPath.pathString)")
        } catch AkashicaError.fileNotFound {
            print("Error: File not found: \(targetPath.pathString)")
            throw ExitCode.failure
        } catch AkashicaError.sessionReadOnly {
            print("Error: Cannot modify read-only session")
            throw ExitCode.failure
        } catch {
            print("Error: Failed to remove file: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
