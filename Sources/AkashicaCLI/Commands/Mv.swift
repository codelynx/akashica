import ArgumentParser
import Foundation
import Akashica

struct Mv: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Move/rename file in virtual filesystem"
    )

    @OptionGroup var storage: StorageOptions

    @Argument(help: "Source path")
    var source: String

    @Argument(help: "Destination path")
    var destination: String

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

        // Resolve paths (relative to virtual CWD)
        let vctx = config.virtualContext()
        let sourcePath = vctx.resolvePath(source)
        let destPath = vctx.resolvePath(destination)

        // Move file
        do {
            try await session.moveFile(from: sourcePath, to: destPath)
            print("Moved \(sourcePath.pathString) → \(destPath.pathString)")
        } catch AkashicaError.fileNotFound {
            print("Error: Source file not found: \(sourcePath.pathString)")
            throw ExitCode.failure
        } catch AkashicaError.sessionReadOnly {
            print("Error: Cannot modify read-only session")
            throw ExitCode.failure
        } catch {
            print("Error: Failed to move file: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
