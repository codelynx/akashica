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

    @OptionGroup var storage: StorageOptions

    @Argument(help: "Directory path (aka:// URI)")
    var path: String

    func run() async throws {
        let config = storage.makeConfig()

        // Parse URI
        let uri = try AkaURI.parse(path)

        // cd only works with current workspace
        guard case .currentWorkspace = uri.scope else {
            print("Error: Cannot cd into \(uri.scopeDescription)")
            print("cd only works within the current workspace")
            throw ExitCode.failure
        }

        // Get session and resolve path
        let session = try await config.getSession(for: uri.scope)
        let targetPath = try config.resolvePathFromURI(uri)

        // Verify directory exists
        do {
            let entries = try await session.listDirectory(at: targetPath)
            _ = entries // Just to verify it's a directory

            // Update virtual CWD
            let vctx = config.virtualContext()
            try vctx.changeDirectory(to: targetPath)

            // Print new path
            print(targetPath.pathString.isEmpty ? "/" : targetPath.pathString)
        } catch AkashicaError.fileNotFound {
            print("Error: Directory not found: \(targetPath.pathString)")
            throw ExitCode.failure
        }
    }
}
