import Foundation
import Akashica

/// Local filesystem storage adapter
public struct LocalStorageAdapter: StorageAdapter {
    public let rootPath: URL

    public init(rootPath: URL) {
        self.rootPath = rootPath
    }

    // MARK: - Path Helpers

    private func objectsPath() -> URL {
        rootPath.appendingPathComponent("objects")
    }

    private func branchesPath() -> URL {
        rootPath.appendingPathComponent("branches")
    }

    private func changesetPath(commit: CommitID) -> URL {
        rootPath
            .appendingPathComponent("changeset")
            .appendingPathComponent(commit.value)
    }

    private func workspacePath(workspace: WorkspaceID) -> URL {
        rootPath
            .appendingPathComponent("changeset")
            .appendingPathComponent(workspace.fullReference)
    }

    // MARK: - Object Operations

    public func readObject(hash: ContentHash) async throws -> Data {
        let path = objectsPath().appendingPathComponent("\(hash.value).dat")
        return try Data(contentsOf: path)
    }

    public func writeObject(data: Data) async throws -> ContentHash {
        let hash = ContentHash(data: data)
        let path = objectsPath().appendingPathComponent("\(hash.value).dat")

        // Create objects directory if needed
        try FileManager.default.createDirectory(
            at: objectsPath(),
            withIntermediateDirectories: true
        )

        try data.write(to: path)
        return hash
    }

    public func objectExists(hash: ContentHash) async throws -> Bool {
        let path = objectsPath().appendingPathComponent("\(hash.value).dat")
        return FileManager.default.fileExists(atPath: path.path)
    }

    // MARK: - Manifest Operations

    public func readManifest(hash: ContentHash) async throws -> Data {
        let path = objectsPath().appendingPathComponent("\(hash.value).dir")
        return try Data(contentsOf: path)
    }

    public func writeManifest(data: Data) async throws -> ContentHash {
        let hash = ContentHash(data: data)
        let path = objectsPath().appendingPathComponent("\(hash.value).dir")

        try FileManager.default.createDirectory(
            at: objectsPath(),
            withIntermediateDirectories: true
        )

        try data.write(to: path)
        return hash
    }

    // MARK: - Commit Operations

    public func readRootManifest(commit: CommitID) async throws -> Data {
        let path = changesetPath(commit: commit).appendingPathComponent(".dir")
        return try Data(contentsOf: path)
    }

    public func writeRootManifest(commit: CommitID, data: Data) async throws {
        let path = changesetPath(commit: commit).appendingPathComponent(".dir")

        try FileManager.default.createDirectory(
            at: changesetPath(commit: commit),
            withIntermediateDirectories: true
        )

        try data.write(to: path)
    }

    public func readCommitMetadata(commit: CommitID) async throws -> CommitMetadata {
        let path = changesetPath(commit: commit).appendingPathComponent("commit.json")
        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CommitMetadata.self, from: data)
    }

    public func writeCommitMetadata(commit: CommitID, metadata: CommitMetadata) async throws {
        let path = changesetPath(commit: commit).appendingPathComponent("commit.json")

        try FileManager.default.createDirectory(
            at: changesetPath(commit: commit),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: path)
    }

    // MARK: - Branch Operations

    public func readBranch(name: String) async throws -> BranchPointer {
        let path = branchesPath().appendingPathComponent("\(name).json")
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(BranchPointer.self, from: data)
    }

    public func updateBranch(
        name: String,
        expectedCurrent: CommitID?,
        newCommit: CommitID
    ) async throws {
        // TODO: Implement proper CAS with file locking
        let path = branchesPath().appendingPathComponent("\(name).json")

        try FileManager.default.createDirectory(
            at: branchesPath(),
            withIntermediateDirectories: true
        )

        let pointer = BranchPointer(head: newCommit)
        let data = try JSONEncoder().encode(pointer)
        try data.write(to: path)
    }

    public func listBranches() async throws -> [String] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: branchesPath(),
            includingPropertiesForKeys: nil
        )
        return contents
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    // MARK: - Workspace Operations

    public func readWorkspaceMetadata(workspace: WorkspaceID) async throws -> WorkspaceMetadata {
        let path = workspacePath(workspace: workspace)
            .appendingPathComponent("workspace.json")
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(WorkspaceMetadata.self, from: data)
    }

    public func writeWorkspaceMetadata(
        workspace: WorkspaceID,
        metadata: WorkspaceMetadata
    ) async throws {
        let path = workspacePath(workspace: workspace)
            .appendingPathComponent("workspace.json")

        try FileManager.default.createDirectory(
            at: workspacePath(workspace: workspace),
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(metadata)
        try data.write(to: path)
    }

    public func deleteWorkspace(workspace: WorkspaceID) async throws {
        let path = workspacePath(workspace: workspace)
        try FileManager.default.removeItem(at: path)
    }

    public func workspaceExists(workspace: WorkspaceID) async throws -> Bool {
        let path = workspacePath(workspace: workspace)
        return FileManager.default.fileExists(atPath: path.path)
    }

    // MARK: - Workspace File Operations

    public func readWorkspaceFile(
        workspace: WorkspaceID,
        path: RepositoryPath
    ) async throws -> Data? {
        let filePath = workspacePath(workspace: workspace)
            .appendingPathComponent("objects")
            .appendingPathComponent(path.pathString)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        return try Data(contentsOf: filePath)
    }

    public func writeWorkspaceFile(
        workspace: WorkspaceID,
        path: RepositoryPath,
        data: Data
    ) async throws {
        let filePath = workspacePath(workspace: workspace)
            .appendingPathComponent("objects")
            .appendingPathComponent(path.pathString)

        try FileManager.default.createDirectory(
            at: filePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try data.write(to: filePath)
    }

    public func deleteWorkspaceFile(
        workspace: WorkspaceID,
        path: RepositoryPath
    ) async throws {
        let filePath = workspacePath(workspace: workspace)
            .appendingPathComponent("objects")
            .appendingPathComponent(path.pathString)

        try FileManager.default.removeItem(at: filePath)
    }

    public func readWorkspaceManifest(
        workspace: WorkspaceID,
        path: RepositoryPath
    ) async throws -> Data? {
        let manifestPath = workspacePath(workspace: workspace)
            .appendingPathComponent("objects")
            .appendingPathComponent(path.pathString)
            .appendingPathComponent(".dir")

        guard FileManager.default.fileExists(atPath: manifestPath.path) else {
            return nil
        }

        return try Data(contentsOf: manifestPath)
    }

    public func writeWorkspaceManifest(
        workspace: WorkspaceID,
        path: RepositoryPath,
        data: Data
    ) async throws {
        let manifestPath = workspacePath(workspace: workspace)
            .appendingPathComponent("objects")
            .appendingPathComponent(path.pathString)
            .appendingPathComponent(".dir")

        try FileManager.default.createDirectory(
            at: manifestPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try data.write(to: manifestPath)
    }

    // MARK: - Workspace COW References

    public func readCOWReference(
        workspace: WorkspaceID,
        path: RepositoryPath
    ) async throws -> COWReference? {
        let refPath = workspacePath(workspace: workspace)
            .appendingPathComponent("refs")
            .appendingPathComponent(path.pathString)

        guard FileManager.default.fileExists(atPath: refPath.path) else {
            return nil
        }

        let data = try Data(contentsOf: refPath)
        return try JSONDecoder().decode(COWReference.self, from: data)
    }

    public func writeCOWReference(
        workspace: WorkspaceID,
        path: RepositoryPath,
        reference: COWReference
    ) async throws {
        let refPath = workspacePath(workspace: workspace)
            .appendingPathComponent("refs")
            .appendingPathComponent(path.pathString)

        try FileManager.default.createDirectory(
            at: refPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(reference)
        try data.write(to: refPath)
    }

    public func deleteCOWReference(
        workspace: WorkspaceID,
        path: RepositoryPath
    ) async throws {
        let refPath = workspacePath(workspace: workspace)
            .appendingPathComponent("refs")
            .appendingPathComponent(path.pathString)

        try FileManager.default.removeItem(at: refPath)
    }
}
