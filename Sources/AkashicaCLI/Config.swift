import Foundation
import ArgumentParser
import Akashica
import AkashicaStorage
import AkashicaS3Storage

/// Reference type (branch or commit)
enum RefType {
    case branch(String)
    case commit(CommitID)

    /// Parse a reference string into branch or commit
    static func parse(_ ref: String) -> RefType {
        if ref.hasPrefix("@") {
            return .commit(CommitID(value: ref))
        } else {
            return .branch(ref)
        }
    }
}

/// Shared configuration for CLI commands
struct Config {
    /// Path to repository root (contains .akashica/)
    let repoPath: URL

    /// Path to .akashica directory
    let akashicaPath: URL

    /// Current working directory
    let cwd: URL

    /// S3 configuration (if using S3 storage)
    let s3Bucket: String?
    let s3Prefix: String?
    let s3Region: String?

    init(repoPath: URL? = nil, s3Bucket: String? = nil, s3Prefix: String? = nil, s3Region: String? = nil) {
        self.cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        if let repoPath = repoPath {
            self.repoPath = repoPath
        } else {
            // Find .akashica directory by walking up from cwd
            self.repoPath = Self.findRepoRoot(from: cwd) ?? cwd
        }

        self.akashicaPath = self.repoPath.appendingPathComponent(".akashica")

        // Try to read config file first, then override with command-line options
        if let configFile = try? ConfigFile.read(from: akashicaPath),
           let storage = configFile.storage {
            // Config file exists - use it as defaults
            self.s3Bucket = s3Bucket ?? (storage.type == "s3" ? storage.bucket : nil)
            self.s3Prefix = s3Prefix ?? storage.prefix
            self.s3Region = s3Region ?? storage.region
        } else {
            // No config file - use command-line options only
            self.s3Bucket = s3Bucket
            self.s3Prefix = s3Prefix
            self.s3Region = s3Region
        }
    }

    /// Find repository root by looking for .akashica directory
    private static func findRepoRoot(from path: URL) -> URL? {
        var current = path
        while current.path != "/" {
            let akashicaPath = current.appendingPathComponent(".akashica")
            if FileManager.default.fileExists(atPath: akashicaPath.path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    /// Check if we're inside a repository (local check only)
    /// For S3, this returns false to allow init; other commands will fail with better errors
    var isInRepository: Bool {
        // Always check for local .akashica directory
        // This works for both local storage and S3 (which uses local workspace tracking)
        return FileManager.default.fileExists(atPath: akashicaPath.path)
    }

    /// Create storage adapter (local filesystem or S3)
    /// This is the primary method for getting a storage adapter
    func createStorage() async throws -> StorageAdapter {
        if let bucket = s3Bucket {
            // S3 storage
            let region = s3Region ?? "us-east-1"
            return try await S3StorageAdapter(
                region: region,
                bucket: bucket,
                keyPrefix: s3Prefix
            )
        } else {
            // Local storage
            return LocalStorageAdapter(rootPath: akashicaPath)
        }
    }

    /// Check if S3 repository exists by probing for initial commit
    /// Used by Init command to prevent duplicate initialization
    func s3RepositoryExists() async throws -> Bool {
        guard s3Bucket != nil else { return false }

        let storage = try await createStorage()
        let initialCommit = CommitID(value: "@0")

        do {
            _ = try await storage.readCommitMetadata(commit: initialCommit)
            return true
        } catch {
            return false
        }
    }

    /// Create and validate storage adapter in one step (optimized for S3)
    /// This is more efficient than calling ensureInRepository() + createStorage() separately
    func createValidatedStorage() async throws -> StorageAdapter {
        let storage = try await createStorage()

        if s3Bucket != nil {
            // S3 mode: Validate repository exists while we have the adapter
            let initialCommit = CommitID(value: "@0")
            do {
                _ = try await storage.readCommitMetadata(commit: initialCommit)
            } catch {
                print("Error: Not in an Akashica repository (S3 bucket '\(s3Bucket!)')")
                if let prefix = s3Prefix {
                    print("  Prefix: \(prefix)")
                }
                print("Run 'akashica init --s3-bucket \(s3Bucket!)' to initialize")
                throw ExitCode.failure
            }
        } else {
            // Local mode: Check directory
            if !isInRepository {
                print("Error: Not in an Akashica repository")
                print("Run 'akashica init' to initialize a repository")
                throw ExitCode.failure
            }
        }

        return storage
    }

    /// Create repository actor (uses validated storage for efficiency)
    func createValidatedRepository() async throws -> AkashicaRepository {
        let storage = try await createValidatedStorage()
        return AkashicaRepository(storage: storage)
    }

    /// Create repository actor
    func createRepository() async throws -> AkashicaRepository {
        let storage = try await createStorage()
        return AkashicaRepository(storage: storage)
    }

    /// Get virtual context for path resolution
    func virtualContext() -> VirtualContext {
        return VirtualContext(akashicaPath: akashicaPath)
    }

    /// Read current workspace ID from .akashica/WORKSPACE
    func currentWorkspace() throws -> WorkspaceID? {
        let workspacePath = akashicaPath.appendingPathComponent("WORKSPACE")

        guard FileManager.default.fileExists(atPath: workspacePath.path) else {
            return nil
        }

        let workspaceRef = try String(contentsOf: workspacePath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return parseWorkspaceID(workspaceRef)
    }

    /// Save current workspace ID to .akashica/WORKSPACE
    func saveWorkspace(_ workspace: WorkspaceID) throws {
        let workspacePath = akashicaPath.appendingPathComponent("WORKSPACE")
        try workspace.fullReference.write(to: workspacePath, atomically: true, encoding: .utf8)
    }

    /// Clear current workspace
    func clearWorkspace() throws {
        let workspacePath = akashicaPath.appendingPathComponent("WORKSPACE")
        try? FileManager.default.removeItem(at: workspacePath)
    }

    /// Parse workspace ID from string (e.g., "@abc$xyz")
    private func parseWorkspaceID(_ ref: String) -> WorkspaceID? {
        let parts = ref.split(separator: "$")
        guard parts.count == 2 else { return nil }

        let baseCommit = CommitID(value: String(parts[0]))
        let suffix = String(parts[1])

        return WorkspaceID(baseCommit: baseCommit, workspaceSuffix: suffix)
    }
}

/// Storage configuration options
struct StorageOptions: ParsableArguments {
    @Option(name: .long, help: "Repository path (default: current directory)")
    var repo: String?

    @Option(name: .long, help: "S3 bucket name (enables S3 storage)")
    var s3Bucket: String?

    @Option(name: .long, help: "S3 key prefix (default: none)")
    var s3Prefix: String?

    @Option(name: .long, help: "AWS region (default: us-east-1)")
    var s3Region: String?

    func makeConfig() -> Config {
        Config(
            repoPath: repo.map { URL(fileURLWithPath: $0) },
            s3Bucket: s3Bucket,
            s3Prefix: s3Prefix,
            s3Region: s3Region
        )
    }
}
