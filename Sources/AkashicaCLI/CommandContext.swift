import Foundation
import ArgumentParser
import Akashica
import AkashicaCore
import AkashicaStorage
import AkashicaS3Storage

/// Centralized context resolution for all CLI commands
///
/// Replaces the old StorageOptions + Config pattern with profile-based context.
/// Commands should use this to get their execution context (profile, workspace, repository).
struct CommandContext {
    /// Resolved profile configuration
    let profile: ProfileConfig

    /// Workspace state (mutable to allow refreshing after updates)
    private(set) var workspace: WorkspaceState

    /// Context resolution source
    let source: ContextResolver.Source

    /// Storage adapter for repository access
    private let storageAdapter: StorageAdapter

    /// Repository actor
    let repository: AkashicaRepository

    private init(
        profile: ProfileConfig,
        workspace: WorkspaceState,
        source: ContextResolver.Source,
        storageAdapter: StorageAdapter
    ) {
        self.profile = profile
        self.workspace = workspace
        self.source = source
        self.storageAdapter = storageAdapter
        self.repository = AkashicaRepository(storage: storageAdapter)
    }

    // MARK: - Context Resolution

    /// Resolve command context from profile flag or environment variable
    ///
    /// Priority:
    /// 1. --profile command-line flag
    /// 2. AKASHICA_PROFILE environment variable
    /// 3. Error (no profile specified)
    static func resolve(profileFlag: String?) async throws -> CommandContext {
        let resolver = ContextResolver()
        let context = try await resolver.resolveContext(commandLineProfile: profileFlag)

        // Create storage adapter
        let storageAdapter = try await createStorageAdapter(config: context.profile)

        return CommandContext(
            profile: context.profile,
            workspace: context.workspace,
            source: context.source,
            storageAdapter: storageAdapter
        )
    }

    private static func createStorageAdapter(config: ProfileConfig) async throws -> StorageAdapter {
        switch config.storage.type {
        case "local":
            guard let path = config.storage.path else {
                throw CommandContextError.missingStorageConfig("path required for local storage")
            }
            let url = URL(fileURLWithPath: path)
            return LocalStorageAdapter(rootPath: url)

        case "s3":
            guard let bucket = config.storage.bucket else {
                throw CommandContextError.missingStorageConfig("bucket required for S3 storage")
            }
            let region = config.storage.region ?? "us-east-1"
            return try await S3StorageAdapter(
                region: region,
                bucket: bucket,
                keyPrefix: config.storage.prefix
            )

        default:
            throw CommandContextError.unsupportedStorageType(config.storage.type)
        }
    }

    // MARK: - Session Management

    /// Get session based on AkaURI scope
    ///
    /// Precedence:
    /// 1. Explicit scope from aka:// URI (branch/commit)
    /// 2. View mode (if active in workspace state)
    /// 3. Current workspace
    func getSession(for scope: AkaURI.Scope) async throws -> AkashicaSession {
        switch scope {
        case .currentWorkspace:
            // Check if view mode is active
            if workspace.view.active, let viewCommit = workspace.view.commit {
                return await repository.view(at: CommitID(value: viewCommit))
            }

            // Use current workspace
            let workspaceID = try parseWorkspaceID(workspace.workspaceId)
            return await repository.session(workspace: workspaceID)

        case .branch(let name):
            do {
                return try await repository.session(branch: name)
            } catch {
                print("Error: Branch '\(name)' not found")
                print("Use 'akashica branch' to see available branches")
                throw ExitCode.failure
            }

        case .commit(let commitID):
            return await repository.view(at: commitID)
        }
    }

    /// Get current workspace ID
    func currentWorkspaceID() throws -> WorkspaceID {
        return try parseWorkspaceID(workspace.workspaceId)
    }

    /// Get current view commit (if in view mode)
    func currentViewCommit() -> CommitID? {
        guard workspace.view.active, let commit = workspace.view.commit else {
            return nil
        }
        return CommitID(value: commit)
    }

    // MARK: - Virtual CWD

    /// Get current virtual working directory
    var virtualCwd: RepositoryPath {
        return RepositoryPath(string: workspace.virtualCwd)
    }

    /// Resolve URI path to absolute RepositoryPath with normalization
    func resolvePathFromURI(_ uri: AkaURI) -> RepositoryPath {
        if uri.isRelativePath {
            // Relative: resolve from virtual CWD with normalization
            return resolveRelativePath(uri.path, from: virtualCwd)
        } else {
            // Absolute: normalize (handles ., .., //)
            return normalizeAbsolutePath(uri.path)
        }
    }

    /// Resolve a relative path from a base directory with normalization
    private func resolveRelativePath(_ input: String, from base: RepositoryPath) -> RepositoryPath {
        var components = base.components

        // Split input by '/' and process each segment
        let segments = input.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        for segment in segments {
            if segment == "." {
                // Current directory - skip
                continue
            } else if segment == ".." {
                // Parent directory - pop last component
                if !components.isEmpty {
                    components.removeLast()
                }
                // If already at root, .. has no effect
            } else {
                // Regular component - append
                components.append(segment)
            }
        }

        return RepositoryPath(components: components)
    }

    /// Normalize an absolute path (handles ., .., //)
    private func normalizeAbsolutePath(_ path: String) -> RepositoryPath {
        var components: [String] = []

        // Remove leading / and split
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let segments = cleaned.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        for segment in segments {
            if segment == "." {
                // Current directory - skip
                continue
            } else if segment == ".." {
                // Parent directory - pop last component
                if !components.isEmpty {
                    components.removeLast()
                }
                // If at root, .. has no effect
            } else {
                // Regular component
                components.append(segment)
            }
        }

        return RepositoryPath(components: components)
    }

    // MARK: - Workspace State Management

    /// Update workspace state and refresh local copy
    mutating func updateWorkspace(_ update: (inout WorkspaceState) -> Void) async throws {
        let stateManager = WorkspaceStateManager()
        try await stateManager.updateState(profile: profile.name, update)

        // Reload workspace state to keep in sync
        self.workspace = try await stateManager.loadState(profile: profile.name)
    }

    /// Update virtual CWD
    mutating func updateVirtualCwd(_ path: RepositoryPath) async throws {
        try await updateWorkspace { state in
            state.virtualCwd = path.pathString
        }
    }

    /// Enter view mode
    mutating func enterView(commit: CommitID) async throws {
        try await updateWorkspace { state in
            state.enterView(commit: commit.value)
        }
    }

    /// Exit view mode
    mutating func exitView() async throws {
        try await updateWorkspace { state in
            state.exitView()
        }
    }

    // MARK: - Helpers

    private func parseWorkspaceID(_ ref: String) throws -> WorkspaceID {
        let parts = ref.split(separator: "$")
        guard parts.count == 2 else {
            throw CommandContextError.invalidWorkspaceID(ref)
        }

        let baseCommit = CommitID(value: String(parts[0]))
        let suffix = String(parts[1])

        return WorkspaceID(baseCommit: baseCommit, workspaceSuffix: suffix)
    }
}

// MARK: - Errors

enum CommandContextError: Error, CustomStringConvertible {
    case missingStorageConfig(String)
    case unsupportedStorageType(String)
    case invalidWorkspaceID(String)

    var description: String {
        switch self {
        case .missingStorageConfig(let detail):
            return "Storage configuration error: \(detail)"
        case .unsupportedStorageType(let type):
            return "Unsupported storage type: '\(type)'"
        case .invalidWorkspaceID(let id):
            return "Invalid workspace ID format: '\(id)'. Expected format: @<commit>$<suffix>"
        }
    }
}
