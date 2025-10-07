import ArgumentParser
import Foundation
import Akashica

struct Ls: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List directory contents from repository",
        discussion: """
        Use aka:// URIs to reference repository content:

        Examples:
          akashica ls                                  # Current virtual CWD
          akashica ls aka:///projects/                 # Absolute path
          akashica ls aka:/tokyo/                      # Relative to virtual CWD
          akashica ls aka://main/                      # Root of branch 'main'
          akashica ls aka://@1234/reports/             # Directory in commit @1234

        Path types:
          aka:///path      - Absolute repository path
          aka:/path        - Relative to virtual CWD
          aka://main/path  - From branch 'main'
          aka://@1234/path - From commit @1234
        """
    )

    @OptionGroup var storage: StorageOptions

    @Argument(help: "Directory path (aka:// URI, defaults to current directory)")
    var path: String?

    func run() async throws {
        let config = storage.makeConfig()

        // Determine target path
        let targetPath: RepositoryPath
        if let pathArg = path {
            // Parse URI
            let uri = try AkaURI.parse(pathArg)

            // Get session and resolve path
            let session = try await config.getSession(for: uri.scope)
            targetPath = try config.resolvePathFromURI(uri)

            // List directory
            try await listDirectory(session: session, path: targetPath)
        } else {
            // No path provided - list current virtual CWD
            // This requires current workspace
            guard let workspace = try config.currentWorkspace() else {
                print("Error: No active workspace")
                print("Run 'akashica checkout <branch>' to create a workspace")
                throw ExitCode.failure
            }

            let repo = try await config.createValidatedRepository()
            let session = await repo.session(workspace: workspace)
            let vctx = config.virtualContext()
            targetPath = vctx.currentDirectory()

            try await listDirectory(session: session, path: targetPath)
        }
    }

    private func listDirectory(session: AkashicaSession, path: RepositoryPath) async throws {
        do {
            let entries = try await session.listDirectory(at: path)

            if entries.isEmpty {
                // Empty directory
                return
            }

            // Sort: directories first, then files, alphabetically
            let sorted = entries.sorted { lhs, rhs in
                if lhs.type == .directory && rhs.type != .directory {
                    return true
                } else if lhs.type != .directory && rhs.type == .directory {
                    return false
                } else {
                    return lhs.name < rhs.name
                }
            }

            // Print entries
            for entry in sorted {
                let typeIndicator = entry.type == .directory ? "/" : ""
                let sizeString = formatSize(entry.size)
                print("\(entry.name)\(typeIndicator)  (\(sizeString))")
            }
        } catch AkashicaError.fileNotFound {
            print("Error: Directory not found: \(path.pathString)")
            throw ExitCode.failure
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes)B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1fK", Double(bytes) / 1024.0)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1fM", Double(bytes) / (1024.0 * 1024.0))
        } else {
            return String(format: "%.1fG", Double(bytes) / (1024.0 * 1024.0 * 1024.0))
        }
    }
}
