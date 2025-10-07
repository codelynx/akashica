import Foundation

/// Session actor (independent, stateful)
public actor AkashicaSession {
    private let repository: AkashicaRepository
    private let storage: StorageAdapter

    /// Changeset this session is tied to (immutable after creation)
    public let changeset: ChangesetRef

    /// Optional branch name (for context, not used in operations)
    public let branch: String?

    /// Is this session read-only?
    public var isReadOnly: Bool { changeset.isReadOnly }

    init(
        repository: AkashicaRepository,
        storage: StorageAdapter,
        changeset: ChangesetRef,
        branch: String? = nil
    ) {
        self.repository = repository
        self.storage = storage
        self.changeset = changeset
        self.branch = branch
    }

    // MARK: - Reading Files

    /// Read file from this session's changeset
    public func readFile(at path: RepositoryPath) async throws -> Data {
        switch changeset {
        case .commit(let commitID):
            return try await readFileFromCommit(commitID, path: path)

        case .workspace(let workspaceID):
            return try await readFileFromWorkspace(workspaceID, path: path)
        }
    }

    /// List directory from this session's changeset
    public func listDirectory(at path: RepositoryPath) async throws -> [DirectoryEntry] {
        switch changeset {
        case .commit(let commitID):
            return try await listDirectoryFromCommit(commitID, path: path)

        case .workspace(let workspaceID):
            return try await listDirectoryFromWorkspace(workspaceID, path: path)
        }
    }

    /// Check if file exists
    public func fileExists(at path: RepositoryPath) async throws -> Bool {
        do {
            _ = try await readFile(at: path)
            return true
        } catch AkashicaError.fileNotFound {
            return false
        }
    }

    // MARK: - Writing Files (workspace only)

    /// Write file to workspace
    /// - Throws: AkashicaError.sessionReadOnly if session is on a commit
    public func writeFile(_ data: Data, to path: RepositoryPath) async throws {
        guard case .workspace(let workspaceID) = changeset else {
            throw AkashicaError.sessionReadOnly
        }

        // Write file to workspace
        try await storage.writeWorkspaceFile(
            workspace: workspaceID,
            path: path,
            data: data
        )

        // Update parent directory manifests
        try await updateWorkspaceManifests(workspace: workspaceID, for: path)
    }

    /// Delete file in workspace
    /// - Throws: AkashicaError.sessionReadOnly if session is on a commit
    public func deleteFile(at path: RepositoryPath) async throws {
        guard case .workspace(let workspaceID) = changeset else {
            throw AkashicaError.sessionReadOnly
        }

        // Delete file from workspace
        try await storage.deleteWorkspaceFile(
            workspace: workspaceID,
            path: path
        )

        // Update parent directory manifests
        try await updateWorkspaceManifests(workspace: workspaceID, for: path)
    }

    /// Rename/move file in workspace
    /// - Throws: AkashicaError.sessionReadOnly if session is on a commit
    public func moveFile(from: RepositoryPath, to: RepositoryPath) async throws {
        guard case .workspace = changeset else {
            throw AkashicaError.sessionReadOnly
        }

        // Read source file
        let data = try await readFile(at: from)

        // Check if file content has changed
        // If unchanged, create COW reference
        // For now, simple implementation: just copy
        try await writeFile(data, to: to)
        try await deleteFile(at: from)
    }

    // MARK: - Status & Diff

    /// Get status of workspace
    /// - Throws: AkashicaError.sessionReadOnly if session is on a commit
    public func status() async throws -> WorkspaceStatus {
        guard case .workspace = changeset else {
            throw AkashicaError.sessionReadOnly
        }

        // TODO: Implement workspace status
        // Compare workspace manifests with base commit
        return WorkspaceStatus(
            modified: [],
            added: [],
            deleted: [],
            renamed: []
        )
    }

    /// Diff this changeset against another commit
    public func diff(against commit: CommitID) async throws -> [FileChange] {
        // TODO: Implement diff
        return []
    }

    // MARK: - Internal Helpers

    private func readFileFromCommit(_ commitID: CommitID, path: RepositoryPath) async throws -> Data {
        // Import AkashicaCore for manifest parsing
        // For now, inline simple parsing to avoid circular dependency

        // 1. Read commit root manifest
        let rootData = try await storage.readRootManifest(commit: commitID)

        // 2. Traverse directory manifests to find file
        var currentManifestData = rootData
        var currentPath = path.components

        // Traverse down the directory tree
        while !currentPath.isEmpty {
            let component = currentPath.removeFirst()
            let isLastComponent = currentPath.isEmpty

            // Parse current manifest
            let entries = try parseManifest(currentManifestData)

            // Find entry for this component
            guard let entry = entries.first(where: { $0.name == component }) else {
                throw AkashicaError.fileNotFound(path)
            }

            if isLastComponent {
                // This is the file we're looking for
                if entry.isDirectory {
                    throw AkashicaError.fileNotFound(path) // Expected file, got directory
                }
                // 3. Read object by hash
                return try await storage.readObject(hash: ContentHash(value: entry.hash))
            } else {
                // This should be a directory, continue traversing
                if !entry.isDirectory {
                    throw AkashicaError.fileNotFound(path) // Expected directory, got file
                }
                // Read next manifest
                currentManifestData = try await storage.readManifest(hash: ContentHash(value: entry.hash))
            }
        }

        // Empty path (root)
        throw AkashicaError.fileNotFound(path)
    }

    // Simple manifest parsing (inline to avoid dependency issues)
    private func parseManifest(_ data: Data) throws -> [(name: String, hash: String, size: Int64, isDirectory: Bool)] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw AkashicaError.invalidManifest("Invalid encoding")
        }

        return try content
            .split(separator: "\n")
            .filter { !$0.isEmpty }
            .map { line in
                let parts = line.split(separator: ":", maxSplits: 2)
                guard parts.count == 3 else {
                    throw AkashicaError.invalidManifest("Invalid format: \(line)")
                }

                let hash = String(parts[0])
                guard let size = Int64(parts[1]) else {
                    throw AkashicaError.invalidManifest("Invalid size: \(parts[1])")
                }
                let name = String(parts[2])

                let isDirectory = name.hasSuffix("/")
                let cleanName = isDirectory ? String(name.dropLast()) : name

                return (name: cleanName, hash: hash, size: size, isDirectory: isDirectory)
            }
    }

    private func readFileFromWorkspace(_ workspaceID: WorkspaceID, path: RepositoryPath) async throws -> Data {
        // Try to read from workspace first
        if let data = try await storage.readWorkspaceFile(workspace: workspaceID, path: path) {
            return data
        }

        // Check for COW reference
        if let cowRef = try await storage.readCOWReference(workspace: workspaceID, path: path) {
            // Read from base commit using hash
            return try await storage.readObject(hash: cowRef.hash)
        }

        // Fall back to base commit
        let metadata = try await storage.readWorkspaceMetadata(workspace: workspaceID)
        return try await readFileFromCommit(metadata.base, path: path)
    }

    private func listDirectoryFromCommit(_ commitID: CommitID, path: RepositoryPath) async throws -> [DirectoryEntry] {
        // TODO: Implement commit directory listing
        fatalError("Not implemented yet")
    }

    private func listDirectoryFromWorkspace(_ workspaceID: WorkspaceID, path: RepositoryPath) async throws -> [DirectoryEntry] {
        // TODO: Implement workspace directory listing
        // Merge workspace manifest with base commit manifest
        fatalError("Not implemented yet")
    }

    private func updateWorkspaceManifests(workspace: WorkspaceID, for path: RepositoryPath) async throws {
        // TODO: Update .dir manifests for all parent directories
        // This ensures the directory tree is consistent
    }
}
