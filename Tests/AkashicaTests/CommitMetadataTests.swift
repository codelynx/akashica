import XCTest
@testable import Akashica
@testable import AkashicaStorage

final class CommitMetadataTests: XCTestCase {
    var tempDir: URL!
    var storage: LocalStorageAdapter!
    var repository: AkashicaRepository!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashica-metadata-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        storage = LocalStorageAdapter(rootPath: tempDir)
        repository = AkashicaRepository(storage: storage)

        // Create initial commit with metadata
        let initialCommit = CommitID(value: "@1000")
        let emptyManifest = Data()
        try await storage.writeRootManifest(commit: initialCommit, data: emptyManifest)

        let initialMetadata = CommitMetadata(
            message: "Initial commit",
            author: "test-user",
            timestamp: Date(),
            parent: nil
        )
        try await storage.writeCommitMetadata(commit: initialCommit, metadata: initialMetadata)

        let branch = BranchPointer(head: initialCommit)
        try await storage.updateBranch(name: "main", expectedCurrent: nil, newCommit: initialCommit)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Metadata Storage Tests

    func testPublishWorkspaceStoresMetadata() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.writeFile("Test content".data(using: .utf8)!, to: RepositoryPath(string: "test.txt"))

        let commitID = try await repository.publishWorkspace(
            workspace,
            toBranch: "main",
            message: "Add test file",
            author: "alice"
        )

        let metadata = try await repository.commitMetadata(commitID)
        XCTAssertEqual(metadata.message, "Add test file")
        XCTAssertEqual(metadata.author, "alice")
        XCTAssertNotNil(metadata.parent)
        XCTAssertEqual(metadata.parent?.value, "@1000")
    }

    func testPublishWorkspaceUsesDefaultAuthor() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.writeFile("Test content".data(using: .utf8)!, to: RepositoryPath(string: "test.txt"))

        let commitID = try await repository.publishWorkspace(
            workspace,
            toBranch: "main",
            message: "Add test file"
        )

        let metadata = try await repository.commitMetadata(commitID)
        XCTAssertEqual(metadata.author, "system")
    }

    func testCommitMetadataTimestamp() async throws {
        let before = Date().addingTimeInterval(-1.0) // 1 second buffer
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.writeFile("Test content".data(using: .utf8)!, to: RepositoryPath(string: "test.txt"))

        let commitID = try await repository.publishWorkspace(
            workspace,
            toBranch: "main",
            message: "Test commit"
        )
        let after = Date().addingTimeInterval(1.0) // 1 second buffer

        let metadata = try await repository.commitMetadata(commitID)
        XCTAssertGreaterThanOrEqual(metadata.timestamp, before)
        XCTAssertLessThanOrEqual(metadata.timestamp, after)
    }

    // MARK: - Commit History Tests

    func testCommitHistorySingleCommit() async throws {
        let history = try await repository.commitHistory(branch: "main", limit: 10)

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].commit.value, "@1000")
        XCTAssertEqual(history[0].metadata.message, "Initial commit")
        XCTAssertEqual(history[0].metadata.author, "test-user")
        XCTAssertNil(history[0].metadata.parent)
    }

    func testCommitHistoryMultipleCommits() async throws {
        // Create second commit
        let workspace1 = try await repository.createWorkspace(fromBranch: "main")
        let session1 = await repository.session(workspace: workspace1)
        try await session1.writeFile("First".data(using: .utf8)!, to: RepositoryPath(string: "first.txt"))
        let commit2 = try await repository.publishWorkspace(workspace1, toBranch: "main", message: "Second commit", author: "alice")

        // Create third commit
        let workspace2 = try await repository.createWorkspace(fromBranch: "main")
        let session2 = await repository.session(workspace: workspace2)
        try await session2.writeFile("Second".data(using: .utf8)!, to: RepositoryPath(string: "second.txt"))
        let commit3 = try await repository.publishWorkspace(workspace2, toBranch: "main", message: "Third commit", author: "bob")

        let history = try await repository.commitHistory(branch: "main", limit: 10)

        XCTAssertEqual(history.count, 3)

        // Should be in reverse chronological order
        XCTAssertEqual(history[0].commit, commit3)
        XCTAssertEqual(history[0].metadata.message, "Third commit")
        XCTAssertEqual(history[0].metadata.author, "bob")
        XCTAssertEqual(history[0].metadata.parent, commit2)

        XCTAssertEqual(history[1].commit, commit2)
        XCTAssertEqual(history[1].metadata.message, "Second commit")
        XCTAssertEqual(history[1].metadata.author, "alice")
        XCTAssertEqual(history[1].metadata.parent?.value, "@1000")

        XCTAssertEqual(history[2].commit.value, "@1000")
        XCTAssertEqual(history[2].metadata.message, "Initial commit")
        XCTAssertNil(history[2].metadata.parent)
    }

    func testCommitHistoryRespectLimit() async throws {
        // Create 5 commits
        for i in 1...5 {
            let workspace = try await repository.createWorkspace(fromBranch: "main")
            let session = await repository.session(workspace: workspace)
            try await session.writeFile("Content \(i)".data(using: .utf8)!, to: RepositoryPath(string: "file\(i).txt"))
            _ = try await repository.publishWorkspace(workspace, toBranch: "main", message: "Commit \(i)")
        }

        let history = try await repository.commitHistory(branch: "main", limit: 3)

        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0].metadata.message, "Commit 5")
        XCTAssertEqual(history[1].metadata.message, "Commit 4")
        XCTAssertEqual(history[2].metadata.message, "Commit 3")
    }

    func testCommitHistoryDefaultLimit() async throws {
        // Create 15 commits (more than default limit of 10)
        for i in 1...15 {
            let workspace = try await repository.createWorkspace(fromBranch: "main")
            let session = await repository.session(workspace: workspace)
            try await session.writeFile("Content \(i)".data(using: .utf8)!, to: RepositoryPath(string: "file\(i).txt"))
            _ = try await repository.publishWorkspace(workspace, toBranch: "main", message: "Commit \(i)")
        }

        let history = try await repository.commitHistory(branch: "main")

        XCTAssertEqual(history.count, 10)
        XCTAssertEqual(history[0].metadata.message, "Commit 15")
        XCTAssertEqual(history[9].metadata.message, "Commit 6")
    }

    // MARK: - Metadata Serialization Tests

    func testCommitMetadataCodable() throws {
        let metadata = CommitMetadata(
            message: "Test commit",
            author: "test-user",
            timestamp: Date(),
            parent: CommitID(value: "@1234")
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CommitMetadata.self, from: data)

        XCTAssertEqual(decoded.message, metadata.message)
        XCTAssertEqual(decoded.author, metadata.author)
        XCTAssertEqual(decoded.parent, metadata.parent)
        // Timestamps might have slight precision differences, so compare within 1 second
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, metadata.timestamp.timeIntervalSince1970, accuracy: 1.0)
    }

    func testCommitMetadataWithNilParent() throws {
        let metadata = CommitMetadata(
            message: "Initial commit",
            author: "test-user",
            timestamp: Date(),
            parent: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CommitMetadata.self, from: data)

        XCTAssertEqual(decoded.message, metadata.message)
        XCTAssertEqual(decoded.author, metadata.author)
        XCTAssertNil(decoded.parent)
    }

    func testCommitMetadataHashable() {
        let metadata1 = CommitMetadata(
            message: "Test",
            author: "alice",
            timestamp: Date(timeIntervalSince1970: 1000),
            parent: CommitID(value: "@1234")
        )

        let metadata2 = CommitMetadata(
            message: "Test",
            author: "alice",
            timestamp: Date(timeIntervalSince1970: 1000),
            parent: CommitID(value: "@1234")
        )

        let metadata3 = CommitMetadata(
            message: "Different",
            author: "alice",
            timestamp: Date(timeIntervalSince1970: 1000),
            parent: CommitID(value: "@1234")
        )

        XCTAssertEqual(metadata1, metadata2)
        XCTAssertNotEqual(metadata1, metadata3)

        let set: Set = [metadata1, metadata2, metadata3]
        XCTAssertEqual(set.count, 2) // metadata1 and metadata2 are equal
    }
}
