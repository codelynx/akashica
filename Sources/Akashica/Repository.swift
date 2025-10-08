import Foundation
import AkashicaCore

/// Main repository actor (stateless)
public actor AkashicaRepository {
    private let storage: StorageAdapter

    public init(storage: StorageAdapter) {
        self.storage = storage
    }

    // MARK: - Session Factory

    /// Create session on a commit (read-only)
    /// Multiple sessions on same commit are independent
    public func session(commit: CommitID) -> AkashicaSession {
        AkashicaSession(
            repository: self,
            storage: storage,
            changeset: .commit(commit)
        )
    }

    /// Create session on a workspace (read-write)
    /// Multiple sessions on different workspaces are independent
    public func session(workspace: WorkspaceID) -> AkashicaSession {
        AkashicaSession(
            repository: self,
            storage: storage,
            changeset: .workspace(workspace)
        )
    }

    /// Create session on branch head (read-only)
    public func session(branch: String) async throws -> AkashicaSession {
        let pointer = try await storage.readBranch(name: branch)
        return AkashicaSession(
            repository: self,
            storage: storage,
            changeset: .commit(pointer.head),
            branch: branch
        )
    }

    // MARK: - Convenience Methods

    /// Create a read-only view at a specific commit
    ///
    /// This is a convenience method that creates a session pointing to a specific
    /// commit in the history chain. Use this to inspect the state of the repository
    /// at any point in time.
    ///
    /// Example:
    /// ```swift
    /// // Given chain: @1000 <- @1020 <- @1125
    /// let view = repo.view(at: CommitID(value: "@1020"))
    /// let files = try await view.listDirectory("/")
    /// // Returns files as they were at @1020
    /// ```
    ///
    /// - Parameter commitID: The commit to view
    /// - Returns: A read-only session at that commit
    public func view(at commitID: CommitID) -> AkashicaSession {
        session(commit: commitID)
    }

    // MARK: - Workspace Creation

    /// Create new workspace from commit
    /// Returns workspace ID for creating a session
    public func createWorkspace(from commit: CommitID) async throws -> WorkspaceID {
        // Generate random workspace suffix
        let suffix = generateWorkspaceSuffix()
        let workspaceID = WorkspaceID(baseCommit: commit, workspaceSuffix: suffix)

        // Create workspace metadata
        let metadata = WorkspaceMetadata(
            base: commit,
            created: Date(),
            creator: "unknown" // TODO: Get from configuration
        )

        // Write metadata to storage
        try await storage.writeWorkspaceMetadata(
            workspace: workspaceID,
            metadata: metadata
        )

        return workspaceID
    }

    /// Create workspace from branch head
    public func createWorkspace(fromBranch branch: String) async throws -> WorkspaceID {
        let pointer = try await storage.readBranch(name: branch)
        return try await createWorkspace(from: pointer.head)
    }

    /// Delete workspace
    public func deleteWorkspace(_ workspace: WorkspaceID) async throws {
        try await storage.deleteWorkspace(workspace: workspace)
    }

    /// Publish workspace as new commit
    public func publishWorkspace(
        _ workspace: WorkspaceID,
        toBranch branch: String,
        message: String,
        author: String = "system"
    ) async throws -> CommitID {
        // 1. Generate new commit ID
        let newCommitID = CommitID(value: "@\(Int.random(in: 1000...9999))")

        // 2. Build commit manifests from workspace
        let rootManifestData = try await buildCommitManifests(
            workspace: workspace,
            path: RepositoryPath(string: "")
        )

        // 3. Write root manifest for new commit
        try await storage.writeRootManifest(commit: newCommitID, data: rootManifestData)

        // 4. Write commit metadata
        let metadata = CommitMetadata(
            message: message,
            author: author,
            timestamp: Date(),
            parent: workspace.baseCommit
        )
        try await storage.writeCommitMetadata(commit: newCommitID, metadata: metadata)

        // 5. Update branch pointer with CAS
        let currentBranchPointer = try await storage.readBranch(name: branch)
        try await storage.updateBranch(
            name: branch,
            expectedCurrent: currentBranchPointer.head,
            newCommit: newCommitID
        )

        // 6. Delete workspace
        try await storage.deleteWorkspace(workspace: workspace)

        return newCommitID
    }

    // MARK: - Branch Operations

    /// List all branches
    public func branches() async throws -> [String] {
        try await storage.listBranches()
    }

    /// Get current commit for branch
    public func currentCommit(branch: String) async throws -> CommitID {
        let pointer = try await storage.readBranch(name: branch)
        return pointer.head
    }

    // MARK: - Commit Metadata

    /// Get metadata for a commit
    public func commitMetadata(_ commit: CommitID) async throws -> CommitMetadata {
        try await storage.readCommitMetadata(commit: commit)
    }

    /// Get commit history for a branch
    /// - Parameters:
    ///   - branch: Branch name to get history for
    ///   - limit: Maximum number of commits to return (default: 10)
    /// - Returns: Array of commit metadata in reverse chronological order
    public func commitHistory(branch: String, limit: Int = 10) async throws -> [(commit: CommitID, metadata: CommitMetadata)] {
        var history: [(commit: CommitID, metadata: CommitMetadata)] = []
        var currentCommit: CommitID? = try await currentCommit(branch: branch)

        while let commit = currentCommit, history.count < limit {
            let metadata = try await storage.readCommitMetadata(commit: commit)
            history.append((commit: commit, metadata: metadata))
            currentCommit = metadata.parent
        }

        return history
    }

    /// Reset branch pointer to a specific commit
    /// - Parameters:
    ///   - name: Branch name to reset
    ///   - target: Target commit to point to
    ///   - force: If true, skip ancestry check (allows non-ancestor resets)
    /// - Throws: `AkashicaError.nonAncestorReset` if target is not an ancestor and force is false
    /// - Throws: `AkashicaError.commitNotFound` if target commit does not exist
    public func resetBranch(name: String, to target: CommitID, force: Bool = false) async throws {
        // Get current branch head
        let current = try await currentCommit(branch: name)

        // If target == current, nothing to do
        if current == target {
            return
        }

        // Verify target commit exists (always, even with --force)
        do {
            _ = try await storage.readCommitMetadata(commit: target)
        } catch {
            throw AkashicaError.commitNotFound(target)
        }

        // Check ancestry unless force is used
        if !force {
            let isAncestor = try await isAncestor(target, of: current)
            if !isAncestor {
                throw AkashicaError.nonAncestorReset(
                    branch: name,
                    current: current,
                    target: target
                )
            }
        }

        // Update branch pointer with CAS
        try await storage.updateBranch(
            name: name,
            expectedCurrent: current,
            newCommit: target
        )
    }

    /// Check if a commit is an ancestor of another commit
    /// - Parameters:
    ///   - ancestor: Potential ancestor commit
    ///   - descendant: Potential descendant commit
    /// - Returns: True if ancestor is in the parent chain of descendant
    public func isAncestor(_ ancestor: CommitID, of descendant: CommitID) async throws -> Bool {
        var current: CommitID? = descendant

        while let commit = current {
            if commit == ancestor {
                return true
            }
            let metadata = try await storage.readCommitMetadata(commit: commit)
            current = metadata.parent
        }

        return false
    }

    /// Get all commits between two commits (exclusive of 'from', inclusive of 'to')
    /// - Parameters:
    ///   - from: Starting commit (not included in result)
    ///   - to: Ending commit (included in result)
    /// - Returns: Array of commits from 'to' back to (but not including) 'from'
    public func commitsBetween(from: CommitID, to: CommitID) async throws -> [(commit: CommitID, metadata: CommitMetadata)] {
        var commits: [(CommitID, CommitMetadata)] = []
        var current: CommitID? = to

        while let commit = current, commit != from {
            let metadata = try await storage.readCommitMetadata(commit: commit)
            commits.append((commit, metadata))
            current = metadata.parent
        }

        return commits
    }

    // MARK: - Internal Helpers

    private func generateWorkspaceSuffix() -> String {
        // Generate random 4-character hex suffix (e.g., "a1b3")
        let characters = "0123456789abcdef"
        return String((0..<4).map { _ in characters.randomElement()! })
    }

    /// Recursively build commit manifests from workspace
    /// Returns manifest data for the given directory
    private func buildCommitManifests(
        workspace: WorkspaceID,
        path: RepositoryPath
    ) async throws -> Data {
        // Get workspace metadata
        let metadata = try await storage.readWorkspaceMetadata(workspace: workspace)

        // Read workspace manifest (if exists)
        let workspaceManifestData = try await storage.readWorkspaceManifest(workspace: workspace, path: path)

        // Read base commit manifest (for fallback)
        let baseManifestData: Data
        do {
            baseManifestData = try await (path.components.isEmpty
                ? storage.readRootManifest(commit: metadata.base)
                : readBaseManifest(commit: metadata.base, path: path))
        } catch {
            baseManifestData = Data()
        }

        // Parse manifests
        let parser = ManifestParser()
        let baseEntries = try? parser.parse(baseManifestData)
        let workspaceEntries = workspaceManifestData.flatMap { try? parser.parse($0) }

        // Create lookup maps
        var entriesMap: [String: ManifestEntry] = [:]

        // If workspace manifest exists, it's the complete source of truth
        // (it tracks deletions by omitting entries)
        if let wsEntries = workspaceEntries {
            for entry in wsEntries {
                entriesMap[entry.name] = entry
            }
        } else {
            // No workspace manifest - use base entries
            for entry in baseEntries ?? [] {
                entriesMap[entry.name] = entry
            }
        }

        // Process entries: write objects and build manifest
        var manifestEntries: [ManifestEntry] = []

        for (name, entry) in entriesMap {
            let filePath = path.components.isEmpty
                ? RepositoryPath(string: name)
                : RepositoryPath(components: path.components + [name])

            if entry.isDirectory {
                // Recursively build subdirectory manifest
                let subManifestData = try await buildCommitManifests(workspace: workspace, path: filePath)
                let hash = try await storage.writeManifest(data: subManifestData)
                manifestEntries.append(ManifestEntry(
                    hash: hash.value,
                    size: Int64(subManifestData.count),
                    name: name,
                    isDirectory: true
                ))
            } else {
                // Check if file is in workspace
                if let fileData = try await storage.readWorkspaceFile(workspace: workspace, path: filePath) {
                    // Write new object
                    let hash = try await storage.writeObject(data: fileData)
                    manifestEntries.append(ManifestEntry(
                        hash: hash.value,
                        size: Int64(fileData.count),
                        name: name,
                        isDirectory: false
                    ))
                } else if let cowRef = try await storage.readCOWReference(workspace: workspace, path: filePath) {
                    // COW reference - reuse hash
                    manifestEntries.append(ManifestEntry(
                        hash: cowRef.hash.value,
                        size: cowRef.size,
                        name: name,
                        isDirectory: false
                    ))
                } else {
                    // Use base entry (unchanged)
                    manifestEntries.append(entry)
                }
            }
        }

        // Build manifest data
        let builder = ManifestBuilder()
        return builder.build(entries: manifestEntries)
    }

    /// Read manifest from base commit at given path
    private func readBaseManifest(commit: CommitID, path: RepositoryPath) async throws -> Data {
        let rootData = try await storage.readRootManifest(commit: commit)
        var currentManifestData = rootData
        var currentPath = path.components

        let parser = ManifestParser()

        while !currentPath.isEmpty {
            let component = currentPath.removeFirst()
            let entries = try parser.parse(currentManifestData)

            guard let entry = entries.first(where: { $0.name == component && $0.isDirectory }) else {
                throw AkashicaError.fileNotFound(path)
            }

            currentManifestData = try await storage.readManifest(hash: ContentHash(value: entry.hash))
        }

        return currentManifestData
    }

    // MARK: - Content Scrubbing

    /// Permanently remove sensitive content from the repository
    ///
    /// **WARNING: This operation is irreversible and destructive.**
    ///
    /// This creates a tombstone marker and deletes the actual content.
    /// All commits referencing this content will return `.objectDeleted`
    /// errors when accessed. History is NOT rewritten - commit manifests
    /// still reference the hash, but the content is permanently gone.
    ///
    /// Use this for:
    /// - Accidentally committed secrets/credentials
    /// - GDPR/compliance data removal
    /// - Security incidents requiring immediate content destruction
    ///
    /// Unlike Git's history-rewriting approach (git-filter-repo, BFG),
    /// Akashica uses tombstones to mark content as deleted without
    /// rewriting commits. This preserves commit integrity while
    /// permanently removing sensitive data.
    ///
    /// - Parameters:
    ///   - hash: Content hash to permanently remove
    ///   - reason: Detailed explanation (required for audit trail)
    ///   - deletedBy: Email/identifier of person authorizing removal
    ///
    /// - Throws: `AkashicaError.fileNotFound` if content doesn't exist
    ///
    /// - SeeAlso: https://docs.github.com/removing-sensitive-data
    public func scrubContent(
        hash: ContentHash,
        reason: String,
        deletedBy: String
    ) async throws {
        // Verify object exists before scrubbing
        guard try await storage.objectExists(hash: hash) else {
            throw AkashicaError.fileNotFound(RepositoryPath(string: hash.value))
        }

        // Get original size before deletion
        let data = try await storage.readObject(hash: hash)
        let originalSize = Int64(data.count)

        // Create tombstone
        let tombstone = Tombstone(
            deletedHash: hash,
            reason: reason,
            timestamp: Date(),
            deletedBy: deletedBy,
            originalSize: originalSize
        )

        // Write tombstone first (safer ordering)
        try await storage.writeTombstone(hash: hash, tombstone: tombstone)

        // Delete actual object
        try await storage.deleteObject(hash: hash)
    }

    /// Convenience method to scrub content by file path in a commit
    ///
    /// Looks up the content hash for the file at the given path in the
    /// specified commit, then scrubs it.
    ///
    /// - Parameters:
    ///   - path: Path to the sensitive file
    ///   - commit: Commit containing the file
    ///   - reason: Why the content is being scrubbed
    ///   - deletedBy: Who authorized the scrubbing
    public func scrubContent(
        at path: RepositoryPath,
        in commit: CommitID,
        reason: String,
        deletedBy: String
    ) async throws {
        // Walk the commit's manifest to find the hash without reading the object
        let hash = try await getHashFromManifest(commit: commit, path: path)

        // Scrub the content
        try await scrubContent(
            hash: hash,
            reason: reason,
            deletedBy: deletedBy
        )
    }

    /// Get content hash for a file from commit manifest without reading object data
    private func getHashFromManifest(commit: CommitID, path: RepositoryPath) async throws -> ContentHash {
        var currentManifestData = try await storage.readRootManifest(commit: commit)
        let parser = ManifestParser()

        // Walk through path components
        for (index, component) in path.components.enumerated() {
            let entries = try parser.parse(currentManifestData)

            guard let entry = entries.first(where: { $0.name == component }) else {
                throw AkashicaError.fileNotFound(path)
            }

            // If this is the last component and it's a file, return its hash
            if index == path.components.count - 1 {
                guard !entry.isDirectory else {
                    throw AkashicaError.fileNotFound(path)
                }
                return ContentHash(value: entry.hash)
            }

            // Otherwise it must be a directory - continue walking
            guard entry.isDirectory else {
                throw AkashicaError.fileNotFound(path)
            }

            // Read the subdirectory manifest
            currentManifestData = try await storage.readManifest(hash: ContentHash(value: entry.hash))
        }

        // Should never reach here with valid path
        throw AkashicaError.fileNotFound(path)
    }

    /// List all tombstones in the repository
    ///
    /// Returns all content hashes that have been scrubbed.
    /// Useful for auditing and compliance reporting.
    ///
    /// - Note: TODO: Add pagination support for repositories with many tombstones
    ///   (v2 feature). Current implementation loads all tombstones into memory.
    public func listScrubbedContent() async throws -> [(ContentHash, Tombstone)] {
        let hashes = try await storage.listTombstones()

        var result: [(ContentHash, Tombstone)] = []
        for hash in hashes {
            if let tombstone = try await storage.readTombstone(hash: hash) {
                result.append((hash, tombstone))
            }
        }

        return result
    }
}
