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

    @Option(name: .long, help: "Profile name (defaults to AKASHICA_PROFILE environment variable)")
    var profile: String?

    @Argument(help: "Source path (aka:// URI)")
    var source: String

    @Argument(help: "Destination path (aka:// URI)")
    var destination: String

    func run() async throws {
        let context = try await CommandContext.resolve(profileFlag: profile)

        // Check if in view mode
        if context.workspace.view.active {
            print("Error: Cannot move files in view mode")
            print("Exit view mode first: akashica view --exit")
            throw ExitCode.failure
        }

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

        // Both must be in the same scope (same workspace)
        guard case .currentWorkspace = srcURI.scope, case .currentWorkspace = dstURI.scope else {
            print("Error: Source and destination must be in the same workspace")
            throw ExitCode.failure
        }

        // Get session
        let session = try await context.getSession(for: srcURI.scope)

        // Resolve paths
        let sourcePath = context.resolvePathFromURI(srcURI)
        let destPath = context.resolvePathFromURI(dstURI)

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
