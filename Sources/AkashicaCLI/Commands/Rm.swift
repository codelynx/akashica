import ArgumentParser
import Foundation
import Akashica

struct Rm: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove file from repository",
        discussion: """
        Remove files from the current workspace (write operation).

        Examples:
          akashica rm aka:///old-file.txt        # Absolute path
          akashica rm aka:/draft.pdf             # Relative path

        Note: Only works with current workspace (aka:/ or aka:///).
        Cannot remove files from branches or commits (read-only).
        """
    )

    @Option(name: .long, help: "Profile name (defaults to AKASHICA_PROFILE environment variable)")
    var profile: String?

    @Argument(help: "File path to remove (aka:// URI)")
    var path: String

    func run() async throws {
        let context = try await CommandContext.resolve(profileFlag: profile)

        // Check if in view mode
        if context.workspace.view.active {
            print("Error: Cannot remove files in view mode")
            print("Exit view mode first: akashica view --exit")
            throw ExitCode.failure
        }

        // Parse URI
        let uri = try AkaURI.parse(path)

        // Validate writable
        guard uri.isWritable else {
            print("Error: Cannot delete from read-only scope: \(uri.scopeDescription)")
            print("Only current workspace (aka:/ or aka:///) supports deletions")
            throw ExitCode.failure
        }

        // Get session and resolve path
        let session = try await context.getSession(for: uri.scope)
        let targetPath = context.resolvePathFromURI(uri)

        // Delete file
        do {
            try await session.deleteFile(at: targetPath)
            print("Removed \(targetPath.pathString)")
        } catch AkashicaError.fileNotFound {
            print("Error: File not found: \(targetPath.pathString)")
            throw ExitCode.failure
        } catch {
            print("Error: Failed to remove file: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}
