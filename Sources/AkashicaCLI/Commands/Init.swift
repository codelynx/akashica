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
        // If no storage options provided, check if already initialized first
        let isInteractive = storage.s3Bucket == nil && storage.repo == nil

        if isInteractive {
            // Check if already initialized (local check only for interactive mode)
            let tempConfig = storage.makeConfig()
            if tempConfig.isInRepository {
                print("Error: Repository already initialized at \(tempConfig.akashicaPath.path)")
                throw ExitCode.failure
            }
        }

        // Interactive prompts if no flags provided
        var finalStorage = storage
        if isInteractive {
            let (bucket, region, prefix) = try promptForStorageConfig()
            finalStorage.s3Bucket = bucket
            finalStorage.s3Region = region
            finalStorage.s3Prefix = prefix
        }

        let config = finalStorage.makeConfig()

        // Check if already initialized (for S3 or when flags were provided)
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
            // Local mode: Check for .akashica directory (non-interactive path)
            if !isInteractive && config.isInRepository {
                print("Error: Repository already initialized at \(config.akashicaPath.path)")
                throw ExitCode.failure
            }
        }

        // Initialize repository in storage backend FIRST
        // Only create local files if this succeeds
        let storageAdapter: StorageAdapter
        do {
            storageAdapter = try await config.createStorage()
        } catch {
            // Provide helpful error message for S3 failures
            if config.s3Bucket != nil {
                print("Error: Failed to connect to S3 bucket '\(config.s3Bucket!)'")
                print("")
                print("Common causes:")
                print("  - Bucket does not exist: Run 'aws s3 mb s3://\(config.s3Bucket!)'")
                print("  - Missing AWS credentials: Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY")
                print("  - Incorrect region: Verify bucket is in '\(config.s3Region ?? "us-east-1")'")
                print("  - Insufficient permissions: Ensure IAM policy allows s3:GetObject, s3:PutObject, s3:ListBucket")
                print("")
                print("You can retry 'akashica init' after fixing the issue.")
            }
            throw ExitCode.failure
        }

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

        // Write commit to storage (this may fail for S3 if bucket doesn't exist)
        do {
            try await storageAdapter.writeRootManifest(commit: initialCommit, data: emptyManifest)
            try await storageAdapter.writeCommitMetadata(commit: initialCommit, metadata: metadata)

            // Create branch
            let expectedCurrent: CommitID? = nil
            try await storageAdapter.updateBranch(
                name: branch,
                expectedCurrent: expectedCurrent,
                newCommit: initialCommit
            )
        } catch {
            // Provide helpful error for S3 initialization failures
            if config.s3Bucket != nil {
                print("Error: Failed to initialize S3 repository")
                print("")
                print("Ensure:")
                print("  - S3 bucket '\(config.s3Bucket!)' exists and is accessible")
                print("  - AWS credentials are valid")
                print("  - IAM permissions allow s3:PutObject and s3:ListBucket")
                print("")
                print("You can retry 'akashica init' after fixing the issue.")
            }
            throw ExitCode.failure
        }

        // SUCCESS! Now create .akashica directory and save config
        // Both local and S3 modes need .akashica/ for config, CWD, and workspace tracking
        try FileManager.default.createDirectory(
            at: config.akashicaPath,
            withIntermediateDirectories: true
        )
        try saveConfig(config: config)

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

    /// Prompt user for storage configuration interactively
    private func promptForStorageConfig() throws -> (s3Bucket: String?, s3Region: String?, s3Prefix: String?) {
        print("Configure storage for your Akashica repository:")
        print("")
        print("Storage type:")
        print("  1) Local filesystem (current directory)")
        print("  2) AWS S3 (cloud storage)")
        print("")
        print("Enter choice [1-2]: ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else {
            throw ExitCode.failure
        }

        switch input {
        case "1":
            // Local storage - use defaults
            return (nil, nil, nil)

        case "2":
            // S3 storage - prompt for details
            print("")
            print("S3 bucket name: ", terminator: "")
            fflush(stdout)
            guard let bucket = readLine()?.trimmingCharacters(in: .whitespaces), !bucket.isEmpty else {
                print("Error: S3 bucket name is required")
                throw ExitCode.failure
            }

            print("AWS region [us-east-1]: ", terminator: "")
            fflush(stdout)
            let regionInput = readLine()?.trimmingCharacters(in: .whitespaces)
            let region = (regionInput?.isEmpty ?? true) ? "us-east-1" : regionInput

            print("S3 key prefix (optional, press Enter to skip): ", terminator: "")
            fflush(stdout)
            let prefixInput = readLine()?.trimmingCharacters(in: .whitespaces)
            let prefix = (prefixInput?.isEmpty ?? true) ? nil : prefixInput

            print("")
            return (bucket, region, prefix)

        default:
            print("Error: Invalid choice. Please enter 1 or 2.")
            throw ExitCode.failure
        }
    }

    /// Save configuration to .akashica/config.json
    private func saveConfig(config: Config) throws {
        let configFile = ConfigFile(storage: ConfigFile.StorageConfig(
            type: config.s3Bucket != nil ? "s3" : "local",
            bucket: config.s3Bucket,
            region: config.s3Region,
            prefix: config.s3Prefix,
            credentials: nil
        ))

        try configFile.write(to: config.akashicaPath)
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
