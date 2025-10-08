import ArgumentParser
import Foundation
import Akashica
import AkashicaCore
import AkashicaStorage

struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Initialize a new Akashica profile and repository"
    )

    @Option(name: .long, help: "Profile name")
    var profile: String

    @Argument(help: "Storage path (local path or s3:// URI)")
    var storagePath: String

    @Option(name: .long, help: "Initial branch name")
    var branch: String = "main"

    func run() async throws {
        let profileManager = ProfileManager()
        let stateManager = WorkspaceStateManager()

        // Check if profile already exists
        if await profileManager.profileExists(name: profile) {
            print("Error: Profile '\(profile)' already exists.")
            print("")
            print("Use a different profile name or delete the existing profile:")
            print("  $ akashica profile delete \(profile)")
            throw ExitCode.failure
        }

        // Parse storage path and create profile config
        let profileConfig: ProfileConfig
        do {
            profileConfig = try parseStoragePath(storagePath, profileName: profile)
        } catch {
            print("Error: \(error)")
            throw ExitCode.failure
        }

        // Detect or create repository
        print("Checking repository at \(storageDisplayPath(profileConfig.storage))...")

        let repositoryExists: Bool
        let repositoryId: String

        do {
            // Try to detect repository
            let detector = RepositoryDetector(storage: profileConfig.storage)
            let result = try await detector.detect()

            switch result {
            case .found(let metadata):
                repositoryExists = true
                repositoryId = metadata.repositoryId
                print("✓ Found existing repository: \(repositoryId)")
                print("")

                // Attach to existing repository
                print("Attach to this repository? [Y/n]: ", terminator: "")
                fflush(stdout)

                let response = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? "y"
                if response != "y" && response != "yes" && !response.isEmpty {
                    print("Cancelled.")
                    throw ExitCode.success
                }

            case .notFound:
                repositoryExists = false
                repositoryId = profileConfig.storage.path?.split(separator: "/").last.map(String.init)
                    ?? profileConfig.storage.bucket
                    ?? "repository"

                print("✗ Repository not found")
                print("")
                print("Create new repository? [Y/n]: ", terminator: "")
                fflush(stdout)

                let response = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? "y"
                if response != "y" && response != "yes" && !response.isEmpty {
                    print("Cancelled.")
                    throw ExitCode.success
                }

                // Create repository
                try await createRepository(config: profileConfig, branch: branch)
                print("")
                print("✓ Created repository at \(storageDisplayPath(profileConfig.storage))")

            case .corrupted(let details):
                print("Error: Repository appears corrupted")
                print(details)
                throw ExitCode.failure
            }
        } catch {
            print("Error checking repository: \(error)")
            throw ExitCode.failure
        }

        // Save profile configuration
        do {
            try await profileManager.saveProfile(profileConfig)
            print("✓ Saved profile: ~/.akashica/configurations/\(profile).json")
        } catch {
            print("Error saving profile: \(error)")
            throw ExitCode.failure
        }

        // Create workspace state
        let initialCommit = repositoryExists
            ? try await getCurrentCommit(config: profileConfig, branch: branch)
            : CommitID(value: "@0")

        let workspaceId = generateWorkspaceId(baseCommit: initialCommit)
        let workspaceState = WorkspaceState(
            profile: profile,
            workspaceId: workspaceId.fullReference,
            baseCommit: initialCommit.value,
            virtualCwd: "/"
        )

        do {
            try await stateManager.saveState(workspaceState)
            print("✓ Workspace state: ~/.akashica/workspaces/\(profile)/state.json")
        } catch {
            print("Error saving workspace state: \(error)")
            throw ExitCode.failure
        }

        print("")
        print("To use this profile:")
        print("  export AKASHICA_PROFILE=\(profile)")
        print("")
        print("You can now run akashica commands from any directory.")
    }

    // MARK: - Storage Path Parsing

    private func parseStoragePath(_ path: String, profileName: String) throws -> ProfileConfig {
        if path.hasPrefix("s3://") {
            // S3 storage not yet supported in v0.10.0
            throw InitError.s3NotYetSupported
        } else {
            // Local filesystem path
            return ProfileConfig(
                name: profileName,
                storage: .local(path: path)
            )
        }
    }

    private func storageDisplayPath(_ storage: ProfileConfig.StorageConfig) -> String {
        switch storage.type {
        case "s3":
            let bucket = storage.bucket!
            if let prefix = storage.prefix, !prefix.isEmpty {
                return "s3://\(bucket)/\(prefix)"
            }
            return "s3://\(bucket)"
        default:
            return storage.path!
        }
    }

    // MARK: - Repository Creation

    private func ensureStorageDirectoryExists(config: ProfileConfig) throws {
        switch config.storage.type {
        case "local":
            let url = URL(fileURLWithPath: config.storage.path!)
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        case "s3":
            // S3 doesn't require directory creation
            break
        default:
            break
        }
    }

    private func createRepository(config: ProfileConfig, branch: String) async throws {
        // Ensure storage directory exists before any writes
        try ensureStorageDirectoryExists(config: config)

        let storageAdapter = try createStorageAdapter(config: config)

        // Create repository metadata
        let repositoryId = config.storage.path?.split(separator: "/").last.map(String.init)
            ?? config.storage.bucket
            ?? "repository"

        let metadata = RepositoryMetadata(
            version: "1.0",
            repositoryId: repositoryId,
            created: Date()
        )

        try await storageAdapter.writeRepositoryMetadata(metadata)

        // Create initial empty commit
        let initialCommit = CommitID(value: "@0")
        let commitMetadata = CommitMetadata(
            message: "Initial commit",
            author: getAuthorName(),
            timestamp: Date(),
            parent: nil
        )

        // Create empty root manifest
        let builder = ManifestBuilder()
        let emptyManifest = builder.build(entries: [])

        // Write commit to storage
        try await storageAdapter.writeRootManifest(commit: initialCommit, data: emptyManifest)
        try await storageAdapter.writeCommitMetadata(commit: initialCommit, metadata: commitMetadata)

        // Create branch
        try await storageAdapter.updateBranch(
            name: branch,
            expectedCurrent: nil,
            newCommit: initialCommit
        )
    }

    private func getCurrentCommit(config: ProfileConfig, branch: String) async throws -> CommitID {
        let storageAdapter = try createStorageAdapter(config: config)
        let branchPointer = try await storageAdapter.readBranch(name: branch)
        return branchPointer.head
    }

    private func createStorageAdapter(config: ProfileConfig) throws -> StorageAdapter {
        switch config.storage.type {
        case "local":
            let url = URL(fileURLWithPath: config.storage.path!)
            return LocalStorageAdapter(rootPath: url)
        case "s3":
            throw InitError.s3NotYetSupported
        default:
            throw InitError.unsupportedStorageType(config.storage.type)
        }
    }

    // MARK: - Workspace ID Generation

    private func generateWorkspaceId(baseCommit: CommitID) -> WorkspaceID {
        let suffix = String(UUID().uuidString.prefix(8).lowercased())
        return WorkspaceID(baseCommit: baseCommit, workspaceSuffix: suffix)
    }

    // MARK: - Author Name

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

// MARK: - Repository Detection

private struct RepositoryDetector {
    let storage: ProfileConfig.StorageConfig

    enum DetectionResult {
        case found(RepositoryMetadata)
        case notFound
        case corrupted(String)
    }

    func detect() async throws -> DetectionResult {
        // For now, only support local detection
        guard storage.type == "local" else {
            return .notFound
        }

        let url = URL(fileURLWithPath: storage.path!)
        let fm = FileManager.default

        let branchesPath = url.appendingPathComponent("branches")
        let metadataPath = url.appendingPathComponent(".akashica.json")

        // Check if repository marker exists
        if fm.fileExists(atPath: metadataPath.path) {
            // Read metadata
            let data = try Data(contentsOf: metadataPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metadata = try decoder.decode(RepositoryMetadata.self, from: data)
            return .found(metadata)
        }

        // Check for legacy structure (branches/)
        if fm.fileExists(atPath: branchesPath.path) {
            // Has branches but no metadata - corrupted or legacy
            return .corrupted("Repository appears to be an older version without .akashica.json")
        }

        return .notFound
    }
}

private struct RepositoryMetadata: Codable {
    let version: String
    let repositoryId: String
    let created: Date
}

// MARK: - Errors

private enum InitError: Error, CustomStringConvertible {
    case s3NotYetSupported
    case unsupportedStorageType(String)

    var description: String {
        switch self {
        case .s3NotYetSupported:
            return """
            S3 storage is not yet supported in v0.10.0.

            For now, please use a local filesystem path:
              $ akashica init --profile myproject /path/to/storage

            S3 support will be added in a future release.
            """
        case .unsupportedStorageType(let type):
            return "Unsupported storage type: '\(type)'"
        }
    }
}

// MARK: - Storage Adapter Extension

extension StorageAdapter {
    fileprivate func writeRepositoryMetadata(_ metadata: RepositoryMetadata) async throws {
        guard let adapter = self as? LocalStorageAdapter else {
            fatalError("Only LocalStorageAdapter supports repository metadata")
        }

        let path = adapter.rootPath.appendingPathComponent(".akashica.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: path)
    }
}
