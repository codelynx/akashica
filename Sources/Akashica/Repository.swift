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
        // 1. Generate new commit ID
        let newCommitID = CommitID(value: "@\(Int.random(in: 1000...9999))")

        // 2. Build commit manifests from workspace
        let rootManifestData = try await buildCommitManifests(
            workspace: workspace,
            path: RepositoryPath(string: "")
        )

        // 3. Write root manifest for new commit
        try await storage.writeRootManifest(commit: newCommitID, data: rootManifestData)

        // 4. Update branch pointer with CAS
        let currentBranchPointer = try await storage.readBranch(name: branch)
        try await storage.updateBranch(
            name: branch,
            expectedCurrent: currentBranchPointer.head,
            newCommit: newCommitID
        )

        // 5. Delete workspace
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
        for entry in baseEntries ?? [] {
            entriesMap[entry.name] = entry
        }
        for entry in workspaceEntries ?? [] {
            entriesMap[entry.name] = entry
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
}
