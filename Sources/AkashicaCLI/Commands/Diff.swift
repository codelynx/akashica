import ArgumentParser
import Foundation
import Akashica

struct Diff: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show changes between workspace and base commit"
    )

    @OptionGroup var storage: StorageOptions

    @Argument(help: "File path to show diff for (optional)")
    var path: String?

    func run() async throws {
        let config = storage.makeConfig()

        // Create validated repository (efficient - one S3 adapter creation)
        let repo = try await config.createValidatedRepository()

        // Get current workspace
        guard let workspace = try config.currentWorkspace() else {
            print("Not in a workspace. Use 'akashica checkout' to create one.")
            throw ExitCode.failure
        }

        let session = await repo.session(workspace: workspace)
        let status = try await session.status()

        // Filter by path if specified
        let targetPath = path.map { RepositoryPath(string: $0) }

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
