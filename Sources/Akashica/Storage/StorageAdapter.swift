import Foundation

/// Abstract storage layer - implement for local/S3/GCS
public protocol StorageAdapter: Sendable {
    // MARK: - Object Operations

    /// Read object data by hash
    func readObject(hash: ContentHash) async throws -> Data

    /// Write object data, returns hash
    func writeObject(data: Data) async throws -> ContentHash

    /// Check if object exists
    func objectExists(hash: ContentHash) async throws -> Bool

    // MARK: - Manifest Operations

    /// Read manifest (.dir file) by hash
    func readManifest(hash: ContentHash) async throws -> Data

    /// Write manifest, returns hash
    func writeManifest(data: Data) async throws -> ContentHash

    // MARK: - Commit Operations

    /// Read root manifest for a commit
    /// - Parameter commit: Commit ID to read root manifest from
    /// - Returns: Raw manifest data from `changeset/@XXXX/.dir`
    func readRootManifest(commit: CommitID) async throws -> Data

    /// Write root manifest for a commit
    /// - Parameters:
    ///   - commit: Commit ID to write root manifest to
    ///   - data: Manifest data to write
    func writeRootManifest(commit: CommitID, data: Data) async throws

    /// Read commit metadata
    /// - Parameter commit: Commit ID to read metadata from
    /// - Returns: Commit metadata (message, author, timestamp, parent)
    func readCommitMetadata(commit: CommitID) async throws -> CommitMetadata

    /// Write commit metadata
    /// - Parameters:
    ///   - commit: Commit ID to write metadata for
    ///   - metadata: Commit metadata to write
    func writeCommitMetadata(commit: CommitID, metadata: CommitMetadata) async throws

    // MARK: - Branch Operations

    /// Read branch pointer
    func readBranch(name: String) async throws -> BranchPointer

    /// Update branch pointer with compare-and-swap
    /// - Parameters:
    ///   - name: Branch name
    ///   - expectedCurrent: Expected current commit (nil for new branch)
    ///   - newCommit: New commit to point to
    /// - Throws: If CAS fails (current != expectedCurrent)
    func updateBranch(
        name: String,
        expectedCurrent: CommitID?,
        newCommit: CommitID
    ) async throws

    /// List all branches
    func listBranches() async throws -> [String]

    // MARK: - Workspace Operations

    /// Read workspace metadata
    func readWorkspaceMetadata(workspace: WorkspaceID) async throws -> WorkspaceMetadata

    /// Write workspace metadata
    func writeWorkspaceMetadata(
        workspace: WorkspaceID,
        metadata: WorkspaceMetadata
    ) async throws

    /// Delete workspace
    func deleteWorkspace(workspace: WorkspaceID) async throws

    /// Check if workspace exists
    func workspaceExists(workspace: WorkspaceID) async throws -> Bool

    // MARK: - Workspace File Operations

    /// Read file from workspace (returns nil if not in workspace)
    func readWorkspaceFile(
        workspace: WorkspaceID,
        path: RepositoryPath
    ) async throws -> Data?

    /// Write file to workspace
    func writeWorkspaceFile(
        workspace: WorkspaceID,
        path: RepositoryPath,
        data: Data
    ) async throws

    /// Delete file from workspace
    func deleteWorkspaceFile(
        workspace: WorkspaceID,
        path: RepositoryPath
    ) async throws

    /// Read workspace directory manifest (returns nil if not in workspace)
    func readWorkspaceManifest(
        workspace: WorkspaceID,
        path: RepositoryPath
    ) async throws -> Data?

    /// Write workspace directory manifest
    func writeWorkspaceManifest(
        workspace: WorkspaceID,
        path: RepositoryPath,
        data: Data
    ) async throws

    // MARK: - Workspace COW References

    /// Read COW reference from workspace (returns nil if not a COW ref)
    func readCOWReference(
        workspace: WorkspaceID,
        path: RepositoryPath
    ) async throws -> COWReference?

    /// Write COW reference to workspace
    func writeCOWReference(
        workspace: WorkspaceID,
        path: RepositoryPath,
        reference: COWReference
    ) async throws

    /// Delete COW reference from workspace
    func deleteCOWReference(
        workspace: WorkspaceID,
        path: RepositoryPath
    ) async throws
}

/// Copy-on-write reference
public struct COWReference: Codable, Sendable {
    public let basePath: RepositoryPath
    public let hash: ContentHash
    public let size: Int64

    public init(basePath: RepositoryPath, hash: ContentHash, size: Int64) {
        self.basePath = basePath
        self.hash = hash
        self.size = size
    }
}
