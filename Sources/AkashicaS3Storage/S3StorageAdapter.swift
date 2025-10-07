import Foundation
import Akashica
import AkashicaCore
import AWSS3
import Smithy
import AWSClientRuntime

/// S3-backed storage adapter for Akashica
///
/// Storage layout in S3 (with sharding):
/// - objects/{hash[0:2]}/{hash[2:4]}/{hash[4:]}.dat  - Content-addressed objects
/// - objects/{hash[0:2]}/{hash[2:4]}/{hash[4:]}.dir  - Content-addressed manifests
/// - objects/{hash[0:2]}/{hash[2:4]}/{hash[4:]}.tomb - Tombstone files
/// - commits/<commitID>/root-manifest                - Commit root manifests
/// - commits/<commitID>/metadata.json                - Commit metadata
/// - branches/<name>                                 - Branch pointers (JSON)
/// - workspaces/<workspaceID>/metadata.json          - Workspace metadata
/// - workspaces/<workspaceID>/files/<path>           - Workspace files
/// - workspaces/<workspaceID>/manifests/<path>       - Workspace manifests
/// - workspaces/<workspaceID>/cow/<path>             - COW references
///
/// Sharding provides 65,536 buckets (4 hex chars), scaling to petabytes while maintaining manageable directory sizes.
///
/// Optional keyPrefix for test isolation:
/// - When provided, all keys are prefixed with "test-runs/<prefix>/"
/// - Allows multiple concurrent test runs without conflicts
/// - Test objects are auto-deleted by S3 lifecycle policy (1 day)
public actor S3StorageAdapter: StorageAdapter {
    private let client: S3Client
    private let bucket: String
    private let keyPrefix: String

    public init(region: String, bucket: String, keyPrefix: String? = nil) async throws {
        self.bucket = bucket
        self.keyPrefix = keyPrefix.map { "test-runs/\($0)/" } ?? ""

        // Create S3 client configuration
        // Uses environment AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
        let config = try await S3Client.S3ClientConfiguration(region: region)
        self.client = S3Client(config: config)
    }

    /// Helper to add prefix to key
    private func prefixedKey(_ path: String) -> String {
        keyPrefix + path
    }

    /// Generate sharded key from content hash
    /// Format: objects/{hash[0:2]}/{hash[2:4]}/{hash[4:]}.{ext}
    /// Example: a3f2b8d9... → objects/a3/f2/b8d9c1e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9.dat
    private func shardedObjectKey(hash: ContentHash, extension ext: String) -> String {
        let hashValue = hash.value
        guard hashValue.count >= 4 else {
            // Fallback for short hashes (shouldn't happen with SHA256)
            return prefixedKey("objects/\(hashValue).\(ext)")
        }

        let firstTwo = String(hashValue.prefix(2))
        let nextTwo = String(hashValue.dropFirst(2).prefix(2))
        let remaining = String(hashValue.dropFirst(4))

        return prefixedKey("objects/\(firstTwo)/\(nextTwo)/\(remaining).\(ext)")
    }

    // MARK: - Content-Addressed Storage (Objects & Manifests)

    public func readObject(hash: ContentHash) async throws -> Data {
        let tombstoneKey = shardedObjectKey(hash: hash, extension: "tomb")
        let objectKey = shardedObjectKey(hash: hash, extension: "dat")

        // Check for tombstone first
        do {
            let tombstoneData = try await getObject(key: tombstoneKey)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let tombstone = try decoder.decode(Tombstone.self, from: tombstoneData)
            throw AkashicaError.objectDeleted(hash: hash, tombstone: tombstone)
        } catch AkashicaError.fileNotFound {
            // No tombstone, proceed to check actual object
        }

        return try await getObject(key: objectKey)
    }

    public func writeObject(data: Data) async throws -> ContentHash {
        let hash = ContentHash(data: data)
        let key = shardedObjectKey(hash: hash, extension: "dat")
        try await putObject(key: key, data: data)
        return hash
    }

    public func objectExists(hash: ContentHash) async throws -> Bool {
        let key = shardedObjectKey(hash: hash, extension: "dat")
        let input = HeadObjectInput(bucket: bucket, key: key)
        do {
            _ = try await client.headObject(input: input)
            return true
        } catch {
            return false
        }
    }

    public func readManifest(hash: ContentHash) async throws -> Data {
        let key = shardedObjectKey(hash: hash, extension: "dir")
        return try await getObject(key: key)
    }

    public func writeManifest(data: Data) async throws -> ContentHash {
        let hash = ContentHash(data: data)
        let key = shardedObjectKey(hash: hash, extension: "dir")
        try await putObject(key: key, data: data)
        return hash
    }

    // MARK: - Commit Storage

    public func readRootManifest(commit: CommitID) async throws -> Data {
        let key = prefixedKey("commits/\(commit.value)/root-manifest")
        return try await getObject(key: key)
    }

    public func writeRootManifest(commit: CommitID, data: Data) async throws {
        let key = prefixedKey("commits/\(commit.value)/root-manifest")
        try await putObject(key: key, data: data)
    }

    public func readCommitMetadata(commit: CommitID) async throws -> CommitMetadata {
        let key = prefixedKey("commits/\(commit.value)/metadata.json")
        let data = try await getObject(key: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CommitMetadata.self, from: data)
    }

    public func writeCommitMetadata(commit: CommitID, metadata: CommitMetadata) async throws {
        let key = prefixedKey("commits/\(commit.value)/metadata.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try await putObject(key: key, data: data)
    }

    // MARK: - Branch Operations

    public func listBranches() async throws -> [String] {
        let prefix = prefixedKey("branches/")
        var branches: [String] = []
        var continuationToken: String? = nil

        repeat {
            let input = ListObjectsV2Input(
                bucket: bucket,
                continuationToken: continuationToken,
                prefix: prefix
            )
            let output = try await client.listObjectsV2(input: input)

            let page = (output.contents ?? []).compactMap { object -> String? in
                guard let key = object.key else { return nil }
                // Strip prefix to get just the branch name
                return String(key.dropFirst(prefix.count))
            }
            branches.append(contentsOf: page)

            continuationToken = output.nextContinuationToken
        } while continuationToken != nil

        return branches
    }

    public func readBranch(name: String) async throws -> BranchPointer {
        let key = prefixedKey("branches/\(name)")
        let data = try await getObject(key: key)
        return try JSONDecoder().decode(BranchPointer.self, from: data)
    }

    public func updateBranch(name: String, expectedCurrent: CommitID?, newCommit: CommitID) async throws {
        let key = prefixedKey("branches/\(name)")

        // Check current value (CAS)
        if let expected = expectedCurrent {
            do {
                let current = try await readBranch(name: name)
                guard current.head == expected else {
                    throw AkashicaError.branchConflict(branch: name, expected: expected, actual: current.head)
                }
            } catch {
                // Branch doesn't exist, but expected value was specified
                throw AkashicaError.branchConflict(branch: name, expected: expected, actual: nil)
            }
        }

        // Write new value
        let pointer = BranchPointer(head: newCommit)
        let data = try JSONEncoder().encode(pointer)
        try await putObject(key: key, data: data)
    }

    // MARK: - Workspace Operations

    public func readWorkspaceMetadata(workspace: WorkspaceID) async throws -> WorkspaceMetadata {
        let key = prefixedKey("workspaces/\(workspace.fullReference)/metadata.json")
        let data = try await getObject(key: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkspaceMetadata.self, from: data)
    }

    public func writeWorkspaceMetadata(workspace: WorkspaceID, metadata: WorkspaceMetadata) async throws {
        let key = prefixedKey("workspaces/\(workspace.fullReference)/metadata.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try await putObject(key: key, data: data)
    }

    public func deleteWorkspace(workspace: WorkspaceID) async throws {
        let prefix = prefixedKey("workspaces/\(workspace.fullReference)/")
        try await deletePrefix(prefix: prefix)
    }

    // MARK: - Workspace Files

    public func readWorkspaceFile(workspace: WorkspaceID, path: RepositoryPath) async throws -> Data? {
        let key = prefixedKey("workspaces/\(workspace.fullReference)/files/\(path.pathString)")
        do {
            return try await getObject(key: key)
        } catch AkashicaError.fileNotFound {
            return nil  // File doesn't exist in workspace
        }
        // Other errors (permissions, network, etc.) propagate
    }

    public func writeWorkspaceFile(workspace: WorkspaceID, path: RepositoryPath, data: Data) async throws {
        let key = prefixedKey("workspaces/\(workspace.fullReference)/files/\(path.pathString)")
        try await putObject(key: key, data: data)
    }

    public func deleteWorkspaceFile(workspace: WorkspaceID, path: RepositoryPath) async throws {
        let key = prefixedKey("workspaces/\(workspace.fullReference)/files/\(path.pathString)")
        try await deleteObject(key: key)
    }

    // MARK: - Workspace Manifests

    public func readWorkspaceManifest(workspace: WorkspaceID, path: RepositoryPath) async throws -> Data? {
        let pathComponent = path.pathString.isEmpty ? "__root__" : path.pathString
        let key = prefixedKey("workspaces/\(workspace.fullReference)/manifests/\(pathComponent)")
        do {
            return try await getObject(key: key)
        } catch AkashicaError.fileNotFound {
            return nil  // Manifest doesn't exist in workspace
        }
        // Other errors (permissions, network, etc.) propagate
    }

    public func writeWorkspaceManifest(workspace: WorkspaceID, path: RepositoryPath, data: Data) async throws {
        let pathComponent = path.pathString.isEmpty ? "__root__" : path.pathString
        let key = prefixedKey("workspaces/\(workspace.fullReference)/manifests/\(pathComponent)")
        try await putObject(key: key, data: data)
    }

    // MARK: - COW References

    public func readCOWReference(workspace: WorkspaceID, path: RepositoryPath) async throws -> COWReference? {
        let key = prefixedKey("workspaces/\(workspace.fullReference)/cow/\(path.pathString)")
        let data: Data
        do {
            data = try await getObject(key: key)
        } catch AkashicaError.fileNotFound {
            return nil  // COW reference doesn't exist
        }
        // Other errors (permissions, network, etc.) propagate
        return try JSONDecoder().decode(COWReference.self, from: data)
    }

    public func writeCOWReference(workspace: WorkspaceID, path: RepositoryPath, reference: COWReference) async throws {
        let key = prefixedKey("workspaces/\(workspace.fullReference)/cow/\(path.pathString)")
        let data = try JSONEncoder().encode(reference)
        try await putObject(key: key, data: data)
    }

    public func deleteCOWReference(workspace: WorkspaceID, path: RepositoryPath) async throws {
        let key = prefixedKey("workspaces/\(workspace.fullReference)/cow/\(path.pathString)")
        try await deleteObject(key: key)
    }

    public func workspaceExists(workspace: WorkspaceID) async throws -> Bool {
        let key = prefixedKey("workspaces/\(workspace.fullReference)/metadata.json")
        let input = HeadObjectInput(bucket: bucket, key: key)
        do {
            _ = try await client.headObject(input: input)
            return true
        } catch {
            return false
        }
    }

    // MARK: - S3 Helpers

    private func getObject(key: String) async throws -> Data {
        let input = GetObjectInput(bucket: bucket, key: key)

        do {
            let output = try await client.getObject(input: input)

            guard let body = output.body else {
                throw AkashicaError.fileNotFound(RepositoryPath(string: key))
            }

            // Use Smithy.ByteStream.readData() to read all data
            guard let data = try await body.readData() else {
                return Data()
            }
            return data
        } catch is NoSuchKey {
            // S3 object doesn't exist
            throw AkashicaError.fileNotFound(RepositoryPath(string: key))
        } catch {
            // Map other errors (permissions, network, etc.)
            throw AkashicaError.storageError(error)
        }
    }

    private func putObject(key: String, data: Data) async throws {
        let input = PutObjectInput(
            body: .data(data),
            bucket: bucket,
            key: key
        )
        _ = try await client.putObject(input: input)
    }

    private func deleteObject(key: String) async throws {
        let input = DeleteObjectInput(bucket: bucket, key: key)
        _ = try await client.deleteObject(input: input)
    }

    private func deletePrefix(prefix: String) async throws {
        // List and delete all objects with prefix, handling pagination
        var continuationToken: String? = nil

        repeat {
            let listInput = ListObjectsV2Input(
                bucket: bucket,
                continuationToken: continuationToken,
                prefix: prefix
            )
            let listOutput = try await client.listObjectsV2(input: listInput)

            guard let objects = listOutput.contents, !objects.isEmpty else {
                return // Nothing to delete
            }

            // Delete batch (S3 limit is 1000 per request, which ListObjectsV2 respects)
            let objectIdentifiers = objects.compactMap { object -> S3ClientTypes.ObjectIdentifier? in
                guard let key = object.key else { return nil }
                return S3ClientTypes.ObjectIdentifier(key: key)
            }

            if !objectIdentifiers.isEmpty {
                let deleteInput = DeleteObjectsInput(
                    bucket: bucket,
                    delete: S3ClientTypes.Delete(objects: objectIdentifiers)
                )
                _ = try await client.deleteObjects(input: deleteInput)
            }

            continuationToken = listOutput.nextContinuationToken
        } while continuationToken != nil
    }

    // MARK: - Tombstone Operations

    public func deleteObject(hash: ContentHash) async throws {
        let key = shardedObjectKey(hash: hash, extension: "dat")
        let input = DeleteObjectInput(bucket: bucket, key: key)
        _ = try await client.deleteObject(input: input)
    }

    public func readTombstone(hash: ContentHash) async throws -> Tombstone? {
        let key = shardedObjectKey(hash: hash, extension: "tomb")

        do {
            let data = try await getObject(key: key)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Tombstone.self, from: data)
        } catch AkashicaError.fileNotFound {
            return nil
        }
    }

    public func writeTombstone(hash: ContentHash, tombstone: Tombstone) async throws {
        let key = shardedObjectKey(hash: hash, extension: "tomb")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(tombstone)

        try await putObject(key: key, data: data)
    }

    public func listTombstones() async throws -> [ContentHash] {
        let prefix = prefixedKey("objects/")
        var tombstones: [ContentHash] = []
        var continuationToken: String? = nil

        repeat {
            let input = ListObjectsV2Input(
                bucket: bucket,
                continuationToken: continuationToken,
                prefix: prefix
            )
            let output = try await client.listObjectsV2(input: input)

            let page = (output.contents ?? []).compactMap { object -> ContentHash? in
                guard let key = object.key,
                      key.hasSuffix(".tomb") else { return nil }

                // Extract hash from sharded path
                // Path: "objects/a3/f2/b8d9c1e4...f9.tomb" or "test-runs/<uuid>/objects/a3/f2/b8d9c1e4...f9.tomb"
                // Hash: a3f2b8d9c1e4...f9
                let pathWithoutPrefix = key.dropFirst(prefix.count)
                let components = pathWithoutPrefix.split(separator: "/")

                guard components.count == 3 else { return nil }
                let firstTwo = components[0]
                let nextTwo = components[1]
                let fileName = components[2].dropLast(5) // Remove ".tomb"

                let hashValue = String(firstTwo) + String(nextTwo) + String(fileName)
                return ContentHash(value: hashValue)
            }
            tombstones.append(contentsOf: page)

            continuationToken = output.nextContinuationToken
        } while continuationToken != nil

        return tombstones
    }
}
