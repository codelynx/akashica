import ArgumentParser
import Foundation
import Akashica

struct Ls: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List directory contents in virtual filesystem"
    )

    @OptionGroup var storage: StorageOptions

    @Argument(help: "Directory path (optional, defaults to current directory)")
    var path: String?

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
        let targetPath = path.map { vctx.resolvePath($0) } ?? vctx.currentDirectory()

        // List directory
        do {
            let entries = try await session.listDirectory(at: targetPath)

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
            print("Error: Directory not found: \(targetPath.pathString)")
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
