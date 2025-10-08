import ArgumentParser
import Foundation
import Akashica

struct Diff: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show changes between workspace and base commit",
        discussion: """
        Shows changes in the current workspace compared to its base commit.

        Examples:
          akashica diff                    # Show all changes
          akashica diff aka:/file.txt      # Show changes for specific file
          akashica diff aka:///docs/       # Show changes in directory

        Note: Only works with current workspace. Cannot diff branches or commits directly.
        """
    )

    @Option(name: .long, help: "Profile name (defaults to AKASHICA_PROFILE environment variable)")
    var profile: String?

    @Argument(help: "File path to show diff for (aka:// URI, optional)")
    var path: String?

    func run() async throws {
        let context = try await CommandContext.resolve(profileFlag: profile)

        // Note: diff currently only works with workspace mode
        // View mode will naturally fail when trying to get workspace
        // TODO: Add --from/--to commit support for view mode compatibility

        // Get workspace and session
        let workspace = try context.currentWorkspaceID()
        let session = await context.repository.session(workspace: workspace)
        let status = try await session.status()

        // Parse path if specified (must be current workspace URI)
        let targetPath: RepositoryPath?
        if let pathArg = path {
            let uri = try AkaURI.parse(pathArg)
            guard case .currentWorkspace = uri.scope else {
                print("Error: diff only works with current workspace")
                print("Use aka:/ or aka:/// for workspace paths")
                throw ExitCode.failure
            }
            targetPath = context.resolvePathFromURI(uri)
        } else {
            targetPath = nil
        }

        // Show added files
        let added = targetPath.map { target in status.added.filter { $0 == target } } ?? status.added
        for filePath in added.sorted() {
            print("\u{001B}[32mAdded: \(filePath.pathString)\u{001B}[0m")

            // Read new content
            let content = try await session.readFile(at: filePath)
            if let text = String(data: content, encoding: .utf8) {
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    print("\u{001B}[32m+ \(line)\u{001B}[0m")
                }
            } else {
                print("  (binary file)")
            }
            print("")
        }

        // Show modified files
        let modified = targetPath.map { target in status.modified.filter { $0 == target } } ?? status.modified
        for filePath in modified.sorted() {
            print("\u{001B}[33mModified: \(filePath.pathString)\u{001B}[0m")
            print("  (showing new content only)")

            let content = try await session.readFile(at: filePath)
            if let text = String(data: content, encoding: .utf8) {
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    print("\u{001B}[33m~ \(line)\u{001B}[0m")
                }
            } else {
                print("  (binary file)")
            }
            print("")
        }

        // Show deleted files
        let deleted = targetPath.map { target in status.deleted.filter { $0 == target } } ?? status.deleted
        for filePath in deleted.sorted() {
            print("\u{001B}[31mDeleted: \(filePath.pathString)\u{001B}[0m")
            print("")
        }

        if added.isEmpty && modified.isEmpty && deleted.isEmpty {
            if let targetPath = targetPath {
                print("No changes to \(targetPath.pathString)")
            } else {
                print("No changes")
            }
        }
    }
}
