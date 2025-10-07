import Foundation

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
        message: String
    ) async throws -> CommitID {
        // TODO: Implement publish logic
        // 1. Collect all changes from workspace
        // 2. Hash modified files and write to objects/
        // 3. Build new manifests
        // 4. Create new commit
        // 5. Update branch pointer with CAS
        // 6. Delete workspace

        fatalError("Not implemented yet")
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

    // MARK: - Internal Helpers

    private func generateWorkspaceSuffix() -> String {
        // Generate random 4-character hex suffix (e.g., "a1b3")
        let characters = "0123456789abcdef"
        return String((0..<4).map { _ in characters.randomElement()! })
    }
}
