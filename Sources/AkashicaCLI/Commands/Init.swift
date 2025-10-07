import ArgumentParser
import Foundation
import Akashica
import AkashicaCore
import AkashicaStorage

struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Initialize a new Akashica repository"
    )

    @OptionGroup var storage: StorageOptions

    @Option(name: .long, help: "Initial branch name")
    var branch: String = "main"

    func run() async throws {
        let config = storage.makeConfig()

        // Check if already initialized
        if config.s3Bucket != nil {
            // S3 mode: Check if repository exists in bucket
            if try await config.s3RepositoryExists() {
                print("Error: Repository already initialized in S3 bucket '\(config.s3Bucket!)'")
                if let prefix = config.s3Prefix {
                    print("  Prefix: \(prefix)")
                }
                throw ExitCode.failure
            }
        } else {
            // Local mode: Check for .akashica directory
            if config.isInRepository {
                print("Error: Repository already initialized at \(config.akashicaPath.path)")
                throw ExitCode.failure
            }
        }

        // Create .akashica directory (only for local storage)
        if config.s3Bucket == nil {
            try FileManager.default.createDirectory(
                at: config.akashicaPath,
                withIntermediateDirectories: true
            )
        }

        // Initialize repository
        let storageAdapter = try await config.createStorage()

        // Create initial empty commit
        let initialCommit = CommitID(value: "@0")
        let metadata = CommitMetadata(
            message: "Initial commit",
            author: getAuthorName(),
            timestamp: Date(),
            parent: nil
        )

        // Create empty root manifest
        let builder = ManifestBuilder()
        let emptyManifest = builder.build(entries: [])

        // Write commit
        try await storageAdapter.writeRootManifest(commit: initialCommit, data: emptyManifest)
        try await storageAdapter.writeCommitMetadata(commit: initialCommit, metadata: metadata)

        // Create branch
        let expectedCurrent: CommitID? = nil
        try await storageAdapter.updateBranch(
            name: branch,
            expectedCurrent: expectedCurrent,
            newCommit: initialCommit
        )

        if let bucket = config.s3Bucket {
            print("Initialized empty Akashica repository in S3 bucket '\(bucket)'")
            if let prefix = config.s3Prefix {
                print("  Prefix: \(prefix)")
            }
        } else {
            print("Initialized empty Akashica repository in \(config.akashicaPath.path)")
        }
        print("Created branch '\(branch)' at \(initialCommit.value)")
    }

    /// Get author name from environment or default
    private func getAuthorName() -> String {
        // Try git config
        if let gitUser = try? String(
            contentsOf: URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".gitconfig")
        ) {
            if let match = gitUser.range(of: "name = (.+)", options: .regularExpression) {
                let name = String(gitUser[match]).replacingOccurrences(of: "name = ", with: "")
                return name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Fall back to USER environment variable
        return ProcessInfo.processInfo.environment["USER"] ?? "unknown"
    }
}
