import ArgumentParser
import Foundation
import Akashica

struct Cd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Change virtual working directory",
        discussion: """
        Note: cd only works with current workspace paths (aka:/ or aka:///).
        You cannot cd into branches or commits.

        Examples:
          akashica cd aka:/tokyo              # Relative path
          akashica cd aka:///japan/tokyo      # Absolute path
          akashica cd aka:/..                 # Parent directory
        """
    )

    @Option(name: .long, help: "Profile name (defaults to AKASHICA_PROFILE environment variable)")
    var profile: String?

    @Argument(help: "Directory path (aka:// URI)")
    var path: String

    func run() async throws {
        var context = try await CommandContext.resolve(profileFlag: profile)

        // Check if in view mode
        if context.workspace.view.active {
            print("Error: Cannot cd in view mode")
            print("Exit view mode first: akashica view --exit")
            throw ExitCode.failure
        }

        // Parse URI
        let uri = try AkaURI.parse(path)

        // cd only works with current workspace
        guard case .currentWorkspace = uri.scope else {
            print("Error: Cannot cd into \(uri.scopeDescription)")
            print("cd only works within the current workspace")
            throw ExitCode.failure
        }

        // Get session and resolve path
        let session = try await context.getSession(for: uri.scope)
        let targetPath = context.resolvePathFromURI(uri)

        // Verify directory exists
        do {
            let entries = try await session.listDirectory(at: targetPath)
            _ = entries // Just to verify it's a directory

            // Update virtual CWD in workspace state
            try await context.updateVirtualCwd(targetPath)

            // Print new path
            print(targetPath.pathString.isEmpty ? "/" : targetPath.pathString)
        } catch AkashicaError.fileNotFound {
            print("Error: Directory not found: \(targetPath.pathString)")
            throw ExitCode.failure
        }
    }
}
