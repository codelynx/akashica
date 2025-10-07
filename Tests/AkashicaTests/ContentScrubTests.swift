import XCTest
@testable import Akashica
@testable import AkashicaCore
@testable import AkashicaStorage

final class ContentScrubTests: XCTestCase {
    var tempDir: URL!
    var storage: LocalStorageAdapter!
    var repo: AkashicaRepository!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashica-scrub-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        storage = LocalStorageAdapter(rootPath: tempDir)
        repo = AkashicaRepository(storage: storage)

        // Initialize main branch
        let initCommit = CommitID(value: "@init")
        let initMetadata = CommitMetadata(
            message: "Initial commit",
            author: "test",
            timestamp: Date(),
            parent: nil
        )
        let emptyManifest = ManifestBuilder().build(entries: [])
        try await storage.writeRootManifest(commit: initCommit, data: emptyManifest)
        try await storage.writeCommitMetadata(commit: initCommit, metadata: initMetadata)
        try await storage.updateBranch(
            name: "main",
            expectedCurrent: nil,
            newCommit: initCommit
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Basic Scrubbing Tests

    func testScrubContentByHash() async throws {
        // Create and write test content
        let testData = "sensitive-secret-key-12345".data(using: .utf8)!
        let hash = try await storage.writeObject(data: testData)

        // Verify object exists and is readable
        let exists = try await storage.objectExists(hash: hash)
        XCTAssertTrue(exists)
        let readData = try await storage.readObject(hash: hash)
        XCTAssertEqual(readData, testData)

        // Scrub the content
        try await repo.scrubContent(
            hash: hash,
            reason: "Accidentally committed API key",
            deletedBy: "security@example.com"
        )

        // Verify object is deleted
        let stillExists = try await storage.objectExists(hash: hash)
        XCTAssertFalse(stillExists)

        // Verify tombstone exists and contains correct data
        let tombstone = try await storage.readTombstone(hash: hash)
        XCTAssertNotNil(tombstone)
        XCTAssertEqual(tombstone?.deletedHash, hash)
        XCTAssertEqual(tombstone?.reason, "Accidentally committed API key")
        XCTAssertEqual(tombstone?.deletedBy, "security@example.com")
        XCTAssertEqual(tombstone?.originalSize, Int64(testData.count))

        // Verify reading the object throws objectDeleted error
        do {
            _ = try await storage.readObject(hash: hash)
            XCTFail("Expected objectDeleted error")
        } catch let error as AkashicaError {
            guard case .objectDeleted(let errorHash, let errorTombstone) = error else {
                XCTFail("Expected objectDeleted error, got \(error)")
                return
            }
            XCTAssertEqual(errorHash, hash)
            XCTAssertEqual(errorTombstone.reason, "Accidentally committed API key")
        }
    }

    func testScrubContentByPath() async throws {
        // Create a commit with a file
        let workspace = try await repo.createWorkspace(fromBranch: "main")
        let session = await repo.session(workspace: workspace)

        let secretPath = RepositoryPath(string: "config/secrets.env")
        let secretData = "API_KEY=super-secret-12345".data(using: .utf8)!
        try await session.writeFile(secretData, to: secretPath)

        // Publish workspace
        let commit = try await repo.publishWorkspace(
            workspace,
            toBranch: "main",
            message: "Add secrets file",
            author: "test"
        )

        // Scrub by path
        try await repo.scrubContent(
            at: secretPath,
            in: commit,
            reason: "Remove accidentally committed secrets",
            deletedBy: "admin@example.com"
        )

        // Verify content is scrubbed
        let hash = ContentHash(data: secretData)
        let exists = try await storage.objectExists(hash: hash)
        XCTAssertFalse(exists)

        let tombstone = try await storage.readTombstone(hash: hash)
        XCTAssertNotNil(tombstone)
        XCTAssertEqual(tombstone?.reason, "Remove accidentally committed secrets")
    }

    func testScrubNonExistentContent() async throws {
        let fakeHash = ContentHash(value: "0000000000000000000000000000000000000000000000000000000000000000")

        do {
            try await repo.scrubContent(
                hash: fakeHash,
                reason: "Test",
                deletedBy: "test"
            )
            XCTFail("Expected fileNotFound error")
        } catch let error as AkashicaError {
            guard case .fileNotFound = error else {
                XCTFail("Expected fileNotFound error, got \(error)")
                return
            }
        }
    }

    func testScrubContentInNestedPath() async throws {
        // Create nested directory structure
        let workspace = try await repo.createWorkspace(fromBranch: "main")
        let session = await repo.session(workspace: workspace)

        let secretPath = RepositoryPath(string: "a/b/c/secret.txt")
        let secretData = "nested-secret".data(using: .utf8)!
        try await session.writeFile(secretData, to: secretPath)

        // Publish
        let commit = try await repo.publishWorkspace(
            workspace,
            toBranch: "main",
            message: "Add nested secret",
            author: "test"
        )

        // Scrub by nested path
        try await repo.scrubContent(
            at: secretPath,
            in: commit,
            reason: "Remove nested secret",
            deletedBy: "security"
        )

        // Verify scrubbed
        let hash = ContentHash(data: secretData)
        let tombstone = try await storage.readTombstone(hash: hash)
        XCTAssertNotNil(tombstone)
    }

    // MARK: - Audit Trail Tests

    func testListScrubbedContent() async throws {
        // Create and scrub multiple files
        let secrets = [
            ("secret1", "password123"),
            ("secret2", "api-key-xyz"),
            ("secret3", "token-abc")
        ]

        for (name, content) in secrets {
            let data = content.data(using: .utf8)!
            let hash = try await storage.writeObject(data: data)
            try await repo.scrubContent(
                hash: hash,
                reason: "Remove \(name)",
                deletedBy: "admin"
            )
        }

        // List scrubbed content
        let scrubbed = try await repo.listScrubbedContent()
        XCTAssertEqual(scrubbed.count, 3)

        // Verify all tombstones are present
        let reasons = scrubbed.map { $0.1.reason }.sorted()
        XCTAssertTrue(reasons.contains("Remove secret1"))
        XCTAssertTrue(reasons.contains("Remove secret2"))
        XCTAssertTrue(reasons.contains("Remove secret3"))
    }

    func testListScrubbedContentEmpty() async throws {
        let scrubbed = try await repo.listScrubbedContent()
        XCTAssertEqual(scrubbed.count, 0)
    }

    // MARK: - Error Message Tests

    func testObjectDeletedErrorMessage() async throws {
        // Create and scrub content
        let testData = "sensitive".data(using: .utf8)!
        let hash = try await storage.writeObject(data: testData)

        try await repo.scrubContent(
            hash: hash,
            reason: "Test reason",
            deletedBy: "test@example.com"
        )

        // Read and verify error message format
        do {
            _ = try await storage.readObject(hash: hash)
            XCTFail("Expected error")
        } catch let error {
            let message = error.localizedDescription

            // Verify single-line format with all components
            XCTAssertTrue(message.contains("Object deleted"))
            XCTAssertTrue(message.contains("hash="))
            XCTAssertTrue(message.contains("reason=Test reason"))
            XCTAssertTrue(message.contains("deletedBy=test@example.com"))
            XCTAssertTrue(message.contains("deletedAt="))

            // Verify no newlines (single line)
            XCTAssertFalse(message.contains("\n"))
        }
    }

    // MARK: - Manifest Walking Tests

    func testGetHashFromManifestOptimization() async throws {
        // Create a large file (10MB)
        let largeData = Data(repeating: 0xFF, count: 10 * 1024 * 1024)

        // Create commit with large file
        let workspace = try await repo.createWorkspace(fromBranch: "main")
        let session = await repo.session(workspace: workspace)

        let path = RepositoryPath(string: "large-file.bin")
        try await session.writeFile(largeData, to: path)

        let commit = try await repo.publishWorkspace(
            workspace,
            toBranch: "main",
            message: "Add large file",
            author: "test"
        )

        // Measure time to scrub by path (should be fast - only reads manifest, not object)
        let start = Date()
        try await repo.scrubContent(
            at: path,
            in: commit,
            reason: "Remove large file",
            deletedBy: "admin"
        )
        let elapsed = Date().timeIntervalSince(start)

        // Should complete quickly (under 1 second) since it doesn't read the 10MB file
        XCTAssertLessThan(elapsed, 1.0, "Scrubbing should be fast - only reads manifest")
    }

    // MARK: - Deduplication Tests

    func testScrubSharedContentAffectsMultipleFiles() async throws {
        // Create two files with identical content
        let sharedData = "shared-content".data(using: .utf8)!

        let workspace = try await repo.createWorkspace(fromBranch: "main")
        let session = await repo.session(workspace: workspace)

        let path1 = RepositoryPath(string: "file1.txt")
        let path2 = RepositoryPath(string: "file2.txt")

        try await session.writeFile(sharedData, to: path1)
        try await session.writeFile(sharedData, to: path2)

        let commit = try await repo.publishWorkspace(
            workspace,
            toBranch: "main",
            message: "Add duplicate files",
            author: "test"
        )

        // Scrub the shared content
        let hash = ContentHash(data: sharedData)
        try await repo.scrubContent(
            hash: hash,
            reason: "Remove shared content",
            deletedBy: "admin"
        )

        // Both files should now be inaccessible
        let readSession = await repo.session(commit: commit)

        do {
            _ = try await readSession.readFile(at: path1)
            XCTFail("Expected error reading file1")
        } catch let error as AkashicaError {
            guard case .objectDeleted = error else {
                XCTFail("Expected objectDeleted error")
                return
            }
        }

        do {
            _ = try await readSession.readFile(at: path2)
            XCTFail("Expected error reading file2")
        } catch let error as AkashicaError {
            guard case .objectDeleted = error else {
                XCTFail("Expected objectDeleted error")
                return
            }
        }
    }

    // MARK: - Tombstone Persistence Tests

    func testTombstonePersistedAcrossAdapterRecreation() async throws {
        // Create and scrub content
        let testData = "persist-test".data(using: .utf8)!
        let hash = try await storage.writeObject(data: testData)

        try await repo.scrubContent(
            hash: hash,
            reason: "Persistence test",
            deletedBy: "test"
        )

        // Create new storage adapter pointing to same directory
        let newStorage = LocalStorageAdapter(rootPath: tempDir)
        let newRepo = AkashicaRepository(storage: newStorage)

        // Verify tombstone is still accessible
        let scrubbed = try await newRepo.listScrubbedContent()
        XCTAssertEqual(scrubbed.count, 1)
        XCTAssertEqual(scrubbed[0].1.reason, "Persistence test")

        // Verify object is still deleted
        do {
            _ = try await newStorage.readObject(hash: hash)
            XCTFail("Expected error")
        } catch let error as AkashicaError {
            guard case .objectDeleted = error else {
                XCTFail("Expected objectDeleted error")
                return
            }
        }
    }
}
