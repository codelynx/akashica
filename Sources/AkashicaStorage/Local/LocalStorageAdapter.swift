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

    /// Generate sharded path from content hash
    /// Format: objects/{hash[0:2]}/{hash[2:4]}/{hash[4:]}.{ext}
    /// Example: a3f2b8d9... → objects/a3/f2/b8d9c1e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9.dat
    private func shardedObjectPath(hash: ContentHash, extension ext: String) -> URL {
        let hashValue = hash.value
        guard hashValue.count >= 4 else {
            // Fallback for short hashes (shouldn't happen with SHA256)
            return objectsPath().appendingPathComponent("\(hashValue).\(ext)")
        }

        let firstTwo = String(hashValue.prefix(2))
        let nextTwo = String(hashValue.dropFirst(2).prefix(2))
        let remaining = String(hashValue.dropFirst(4))

        return objectsPath()
            .appendingPathComponent(firstTwo)
            .appendingPathComponent(nextTwo)
            .appendingPathComponent("\(remaining).\(ext)")
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
        let tombstonePath = shardedObjectPath(hash: hash, extension: "tomb")
        let objectPath = shardedObjectPath(hash: hash, extension: "dat")

        // Check for tombstone first
        if FileManager.default.fileExists(atPath: tombstonePath.path) {
            let tombstoneData = try Data(contentsOf: tombstonePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let tombstone = try decoder.decode(Tombstone.self, from: tombstoneData)
            throw AkashicaError.objectDeleted(hash: hash, tombstone: tombstone)
        }

        // Check if object exists
        guard FileManager.default.fileExists(atPath: objectPath.path) else {
            throw AkashicaError.fileNotFound(RepositoryPath(string: hash.value))
        }

        return try Data(contentsOf: objectPath)
    }

    public func writeObject(data: Data) async throws -> ContentHash {
        let hash = ContentHash(data: data)
        let path = shardedObjectPath(hash: hash, extension: "dat")

        // Create sharded directory structure if needed
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try data.write(to: path)
        return hash
    }

    public func objectExists(hash: ContentHash) async throws -> Bool {
        let path = shardedObjectPath(hash: hash, extension: "dat")
        return FileManager.default.fileExists(atPath: path.path)
    }

    // MARK: - Manifest Operations

    public func readManifest(hash: ContentHash) async throws -> Data {
        let path = shardedObjectPath(hash: hash, extension: "dir")
        return try Data(contentsOf: path)
    }

    public func writeManifest(data: Data) async throws -> ContentHash {
        let hash = ContentHash(data: data)
        let path = shardedObjectPath(hash: hash, extension: "dir")

        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
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

    // MARK: - Tombstone Operations

    public func deleteObject(hash: ContentHash) async throws {
        let path = shardedObjectPath(hash: hash, extension: "dat")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AkashicaError.fileNotFound(RepositoryPath(string: hash.value))
        }
        try FileManager.default.removeItem(at: path)
    }

    public func readTombstone(hash: ContentHash) async throws -> Tombstone? {
        let path = shardedObjectPath(hash: hash, extension: "tomb")

        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }

        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Tombstone.self, from: data)
    }

    public func writeTombstone(hash: ContentHash, tombstone: Tombstone) async throws {
        let path = shardedObjectPath(hash: hash, extension: "tomb")

        // Create sharded directory structure if needed
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tombstone)
        try data.write(to: path)
    }

    public func listTombstones() async throws -> [ContentHash] {
        let objectsDir = objectsPath()

        guard FileManager.default.fileExists(atPath: objectsDir.path) else {
            return []
        }

        var tombstones: [ContentHash] = []

        // Traverse sharded directory structure: objects/a3/f2/*.tomb
        let enumerator = FileManager.default.enumerator(
            at: objectsDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "tomb" else { continue }

            // Reconstruct hash from sharded path
            // Path: objects/a3/f2/b8d9c1e4...f9.tomb
            // Hash: a3f2b8d9c1e4...f9
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            let parent1 = fileURL.deletingLastPathComponent().lastPathComponent
            let parent2 = fileURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent

            let hashValue = parent2 + parent1 + fileName
            tombstones.append(ContentHash(value: hashValue))
        }

        return tombstones
    }
}
