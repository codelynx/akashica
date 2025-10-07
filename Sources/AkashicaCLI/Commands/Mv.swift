import ArgumentParser
import Foundation
import Akashica

struct Mv: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Move/rename file in repository",
        discussion: """
        Move or rename files in the current workspace (write operation).

        Examples:
          akashica mv aka:///draft.pdf aka:///final.pdf    # Rename (absolute)
          akashica mv aka:/old.txt aka:/new.txt            # Rename (relative)
          akashica mv aka:/file.pdf aka:/../archive/       # Move to different dir

        Note: Both source and destination must be in current workspace.
        Cannot move files from/to branches or commits (read-only).
        """
    )

    @OptionGroup var storage: StorageOptions

    @Argument(help: "Source path (aka:// URI)")
    var source: String

    @Argument(help: "Destination path (aka:// URI)")
    var destination: String

    func run() async throws {
        let config = storage.makeConfig()

        // Parse both URIs
        let srcURI = try AkaURI.parse(source)
        let dstURI = try AkaURI.parse(destination)

        // Both must be writable (current workspace only)
        guard srcURI.isWritable else {
            print("Error: Cannot move from read-only scope: \(srcURI.scopeDescription)")
            throw ExitCode.failure
        }
        guard dstURI.isWritable else {
            print("Error: Cannot move to read-only scope: \(dstURI.scopeDescription)")
            throw ExitCode.failure
        }

        // Get session (both must be same workspace)
        let session = try await config.getSession(for: srcURI.scope)

        // Resolve paths
        let sourcePath = try config.resolvePathFromURI(srcURI)
        let destPath = try config.resolvePathFromURI(dstURI)

        // Move file
        do {
            try await session.moveFile(from: sourcePath, to: destPath)
            print("Moved \(sourcePath.pathString) → \(destPath.pathString)")
        } catch AkashicaError.fileNotFound {
            print("Error: Source file not found: \(sourcePath.pathString)")
            throw ExitCode.failure
        } catch {
            print("Error: Failed to move file: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
