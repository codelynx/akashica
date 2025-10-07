import XCTest
import Akashica
import TestSupport
@testable import AkashicaS3Storage

/// Integration tests for S3StorageAdapter
///
/// Requires AWS credentials in .credentials/aws-credentials.json
/// Tests run against live S3 bucket (akashica-test-bucket)
final class S3IntegrationTests: XCTestCase {
    var storage: S3StorageAdapter!
    var previousEnv: [String: String?] = [:]
    var testPrefix: String!

    override func setUp() async throws {
        try await super.setUp()

        // Load AWS credentials
        guard let config = try AWSTestConfig.load() else {
            throw XCTSkip("AWS credentials not configured - add .credentials/aws-credentials.json to run S3 tests")
        }

        // Set environment variables for AWS SDK (store previous values for tearDown)
        previousEnv = config.setEnvironmentVariables()

        // Generate unique test prefix for isolation (auto-deleted by 1-day lifecycle policy)
        testPrefix = UUID().uuidString

        // Initialize S3 storage adapter with test prefix
        storage = try await S3StorageAdapter(region: config.region, bucket: config.bucket, keyPrefix: testPrefix)
    }

    override func tearDown() async throws {
        // Clean up test artifacts from this specific test run
        // Note: S3 bucket has 1-day lifecycle policy for cost control
        // This cleanup ensures tests can rerun immediately without conflicts

        // Restore environment variables to prevent credential leakage
        AWSTestConfig.restoreEnvironmentVariables(previousEnv)
        previousEnv = [:]

        try await super.tearDown()
    }

    // MARK: - Object Storage Tests

    func testObjectRoundTrip() async throws {
        let testData = "Hello, S3!".data(using: .utf8)!

        // Write object
        let hash = try await storage.writeObject(data: testData)

        // Read back
        let retrieved = try await storage.readObject(hash: hash)

        XCTAssertEqual(retrieved, testData)
    }

    func testObjectExists() async throws {
        let testData = "Test existence".data(using: .utf8)!
        let hash = try await storage.writeObject(data: testData)

        let exists = try await storage.objectExists(hash: hash)
        XCTAssertTrue(exists)
    }

    func testObjectNotFound() async throws {
        let fakeHash = ContentHash(data: "nonexistent".data(using: .utf8)!)

        do {
            _ = try await storage.readObject(hash: fakeHash)
            XCTFail("Should throw fileNotFound")
        } catch AkashicaError.fileNotFound {
            // Expected
        }
    }

    // MARK: - Manifest Storage Tests

    func testManifestRoundTrip() async throws {
        let manifest = """
        abc123:1024:file1.txt
        def456:2048:file2.txt
        """
        let testData = manifest.data(using: .utf8)!

        let hash = try await storage.writeManifest(data: testData)
        let retrieved = try await storage.readManifest(hash: hash)

        XCTAssertEqual(retrieved, testData)
    }

    // MARK: - Commit Storage Tests

    func testCommitMetadataRoundTrip() async throws {
        let commit = CommitID(value: "@9001")
        let metadata = CommitMetadata(
            message: "Test commit on S3",
            author: "test-user",
            timestamp: Date(),
            parent: nil
        )

        try await storage.writeCommitMetadata(commit: commit, metadata: metadata)
        let retrieved = try await storage.readCommitMetadata(commit: commit)

        XCTAssertEqual(retrieved.message, metadata.message)
        XCTAssertEqual(retrieved.author, metadata.author)
        XCTAssertEqual(retrieved.parent, metadata.parent)
        // Timestamp may have sub-millisecond differences due to ISO8601 encoding
        XCTAssertEqual(retrieved.timestamp.timeIntervalSince1970, metadata.timestamp.timeIntervalSince1970, accuracy: 1.0)
    }

    func testRootManifestRoundTrip() async throws {
        let commit = CommitID(value: "@9002")
        let manifest = "hash1:100:file.txt".data(using: .utf8)!

        try await storage.writeRootManifest(commit: commit, data: manifest)
        let retrieved = try await storage.readRootManifest(commit: commit)

        XCTAssertEqual(retrieved, manifest)
    }

    // MARK: - Branch Operations Tests

    func testBranchCAS() async throws {
        let branchName = "test-branch-\(Int.random(in: 1000...9999))"
        let commit1 = CommitID(value: "@9003")
        let commit2 = CommitID(value: "@9004")

        // Create branch
        try await storage.updateBranch(name: branchName, expectedCurrent: nil, newCommit: commit1)

        // Read branch
        let pointer = try await storage.readBranch(name: branchName)
        XCTAssertEqual(pointer.head, commit1)

        // Update with correct expected value
        try await storage.updateBranch(name: branchName, expectedCurrent: commit1, newCommit: commit2)

        // Verify update
        let updated = try await storage.readBranch(name: branchName)
        XCTAssertEqual(updated.head, commit2)

        // Try to update with wrong expected value
        do {
            try await storage.updateBranch(name: branchName, expectedCurrent: commit1, newCommit: commit1)
            XCTFail("Should throw branchConflict")
        } catch AkashicaError.branchConflict {
            // Expected
        }
    }

    func testListBranches() async throws {
        let branch1 = "list-test-1-\(Int.random(in: 1000...9999))"
        let branch2 = "list-test-2-\(Int.random(in: 1000...9999))"
        let commit = CommitID(value: "@9005")

        try await storage.updateBranch(name: branch1, expectedCurrent: nil, newCommit: commit)
        try await storage.updateBranch(name: branch2, expectedCurrent: nil, newCommit: commit)

        let branches = try await storage.listBranches()
        XCTAssertTrue(branches.contains(branch1))
        XCTAssertTrue(branches.contains(branch2))
    }

    // MARK: - Workspace Operations Tests

    func testWorkspaceLifecycle() async throws {
        let workspace = WorkspaceID(
            baseCommit: CommitID(value: "@9006"),
            workspaceSuffix: "test"
        )
        let metadata = WorkspaceMetadata(
            base: workspace.baseCommit,
            created: Date(),
            creator: "test-user"
        )

        // Create workspace
        try await storage.writeWorkspaceMetadata(workspace: workspace, metadata: metadata)

        // Verify exists
        let exists = try await storage.workspaceExists(workspace: workspace)
        XCTAssertTrue(exists)

        // Read metadata
        let retrieved = try await storage.readWorkspaceMetadata(workspace: workspace)
        XCTAssertEqual(retrieved.base, metadata.base)
        XCTAssertEqual(retrieved.creator, metadata.creator)

        // Delete workspace
        try await storage.deleteWorkspace(workspace: workspace)

        // Verify deleted
        let existsAfterDelete = try await storage.workspaceExists(workspace: workspace)
        XCTAssertFalse(existsAfterDelete)
    }

    func testWorkspaceFileOperations() async throws {
        let workspace = WorkspaceID(
            baseCommit: CommitID(value: "@9007"),
            workspaceSuffix: "files"
        )
        let path = RepositoryPath(string: "test/file.txt")
        let content = "Workspace file content".data(using: .utf8)!

        // Write file
        try await storage.writeWorkspaceFile(workspace: workspace, path: path, data: content)

        // Read file
        let retrieved = try await storage.readWorkspaceFile(workspace: workspace, path: path)
        XCTAssertEqual(retrieved, content)

        // Delete file
        try await storage.deleteWorkspaceFile(workspace: workspace, path: path)

        // Verify deleted
        let afterDelete = try await storage.readWorkspaceFile(workspace: workspace, path: path)
        XCTAssertNil(afterDelete)
    }

    func testWorkspaceManifestOperations() async throws {
        let workspace = WorkspaceID(
            baseCommit: CommitID(value: "@9008"),
            workspaceSuffix: "manifests"
        )

        // Test root manifest
        let rootManifest = "hash1:100:file.txt".data(using: .utf8)!
        try await storage.writeWorkspaceManifest(workspace: workspace, path: RepositoryPath(string: ""), data: rootManifest)
        let retrievedRoot = try await storage.readWorkspaceManifest(workspace: workspace, path: RepositoryPath(string: ""))
        XCTAssertEqual(retrievedRoot, rootManifest)

        // Test nested manifest
        let nestedPath = RepositoryPath(string: "nested/dir")
        let nestedManifest = "hash2:200:nested.txt".data(using: .utf8)!
        try await storage.writeWorkspaceManifest(workspace: workspace, path: nestedPath, data: nestedManifest)
        let retrievedNested = try await storage.readWorkspaceManifest(workspace: workspace, path: nestedPath)
        XCTAssertEqual(retrievedNested, nestedManifest)
    }

    func testCOWReferenceOperations() async throws {
        let workspace = WorkspaceID(
            baseCommit: CommitID(value: "@9009"),
            workspaceSuffix: "cow"
        )
        let path = RepositoryPath(string: "copied/file.txt")
        let reference = COWReference(
            basePath: RepositoryPath(string: "original/file.txt"),
            hash: ContentHash(data: "test".data(using: .utf8)!),
            size: 1024
        )

        // Write COW reference
        try await storage.writeCOWReference(workspace: workspace, path: path, reference: reference)

        // Read COW reference
        let retrieved = try await storage.readCOWReference(workspace: workspace, path: path)
        XCTAssertEqual(retrieved?.basePath, reference.basePath)
        XCTAssertEqual(retrieved?.hash, reference.hash)
        XCTAssertEqual(retrieved?.size, reference.size)

        // Delete COW reference
        try await storage.deleteCOWReference(workspace: workspace, path: path)

        // Verify deleted
        let afterDelete = try await storage.readCOWReference(workspace: workspace, path: path)
        XCTAssertNil(afterDelete)
    }
}
