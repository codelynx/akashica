import XCTest
@testable import Akashica
@testable import AkashicaStorage

final class DiffTests: XCTestCase {
    var tempDir: URL!
    var storage: LocalStorageAdapter!
    var repository: AkashicaRepository!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashica-diff-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        storage = LocalStorageAdapter(rootPath: tempDir)
        repository = AkashicaRepository(storage: storage)

        // Create initial commit
        let initialCommit = CommitID(value: "@1000")
        let readmeData = "Initial README".data(using: .utf8)!
        let readmeHash = try await storage.writeObject(data: readmeData)
        let rootManifest = "\(readmeHash.value):\(readmeData.count):README.md".data(using: .utf8)!
        try await storage.writeRootManifest(commit: initialCommit, data: rootManifest)

        let initialMetadata = CommitMetadata(
            message: "Initial commit",
            author: "test-user",
            timestamp: Date(),
            parent: nil
        )
        try await storage.writeCommitMetadata(commit: initialCommit, metadata: initialMetadata)

        try await storage.updateBranch(name: "main", expectedCurrent: nil, newCommit: initialCommit)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Commit to Commit Diff

    func testDiffBetweenTwoCommits() async throws {
        // Create second commit with modified file
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.writeFile("Updated README".data(using: .utf8)!, to: RepositoryPath(string: "README.md"))
        try await session.writeFile("New file".data(using: .utf8)!, to: RepositoryPath(string: "new.txt"))

        let commit2 = try await repository.publishWorkspace(workspace, toBranch: "main", message: "Add new file")

        // Diff commit2 against commit1
        let diffSession = await repository.session(commit: commit2)
        let changes = try await diffSession.diff(against: CommitID(value: "@1000"))

        XCTAssertEqual(changes.count, 2)

        let modified = changes.filter { if case .modified = $0.type { return true }; return false }
        let added = changes.filter { if case .added = $0.type { return true }; return false }

        XCTAssertEqual(modified.count, 1)
        XCTAssertEqual(added.count, 1)
        XCTAssertTrue(modified.contains { $0.path == RepositoryPath(string: "README.md") })
        XCTAssertTrue(added.contains { $0.path == RepositoryPath(string: "new.txt") })
    }

    func testDiffWithDeletion() async throws {
        // Create second commit without README
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.deleteFile(at: RepositoryPath(string: "README.md"))
        try await session.writeFile("New file".data(using: .utf8)!, to: RepositoryPath(string: "new.txt"))

        let commit2 = try await repository.publishWorkspace(workspace, toBranch: "main", message: "Delete README")

        // Diff commit2 against commit1
        let diffSession = await repository.session(commit: commit2)
        let changes = try await diffSession.diff(against: CommitID(value: "@1000"))

        XCTAssertEqual(changes.count, 2)

        let deleted = changes.filter { if case .deleted = $0.type { return true }; return false }
        let added = changes.filter { if case .added = $0.type { return true }; return false }

        XCTAssertEqual(deleted.count, 1)
        XCTAssertEqual(added.count, 1)
        XCTAssertTrue(deleted.contains { $0.path == RepositoryPath(string: "README.md") })
        XCTAssertTrue(added.contains { $0.path == RepositoryPath(string: "new.txt") })
    }

    func testDiffWithNoChanges() async throws {
        // Diff commit against itself
        let session = await repository.session(commit: CommitID(value: "@1000"))
        let changes = try await session.diff(against: CommitID(value: "@1000"))

        XCTAssertEqual(changes.count, 0)
    }

    // MARK: - Workspace to Commit Diff

    func testDiffWorkspaceAgainstCommit() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Make changes
        try await session.writeFile("Updated README".data(using: .utf8)!, to: RepositoryPath(string: "README.md"))
        try await session.writeFile("New file".data(using: .utf8)!, to: RepositoryPath(string: "new.txt"))

        // Diff workspace against base commit
        let changes = try await session.diff(against: CommitID(value: "@1000"))

        XCTAssertEqual(changes.count, 2)

        let modified = changes.filter { if case .modified = $0.type { return true }; return false }
        let added = changes.filter { if case .added = $0.type { return true }; return false }

        XCTAssertEqual(modified.count, 1)
        XCTAssertEqual(added.count, 1)
    }

    func testDiffWorkspaceWithDeletion() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.deleteFile(at: RepositoryPath(string: "README.md"))

        let changes = try await session.diff(against: CommitID(value: "@1000"))

        XCTAssertEqual(changes.count, 1)

        if case .deleted = changes[0].type {
            XCTAssertEqual(changes[0].path, RepositoryPath(string: "README.md"))
        } else {
            XCTFail("Expected deletion")
        }
    }

    // MARK: - Nested Directory Diff

    func testDiffWithNestedDirectories() async throws {
        // Create base commit with nested structure
        let workspace1 = try await repository.createWorkspace(fromBranch: "main")
        let session1 = await repository.session(workspace: workspace1)

        try await session1.writeFile("Tokyo".data(using: .utf8)!, to: RepositoryPath(string: "asia/japan/tokyo.txt"))
        try await session1.writeFile("Kyoto".data(using: .utf8)!, to: RepositoryPath(string: "asia/japan/kyoto.txt"))

        let commit1 = try await repository.publishWorkspace(workspace1, toBranch: "main", message: "Add nested files")

        // Create second commit with changes
        let workspace2 = try await repository.createWorkspace(fromBranch: "main")
        let session2 = await repository.session(workspace: workspace2)

        try await session2.writeFile("Updated Tokyo".data(using: .utf8)!, to: RepositoryPath(string: "asia/japan/tokyo.txt"))
        try await session2.deleteFile(at: RepositoryPath(string: "asia/japan/kyoto.txt"))
        try await session2.writeFile("Osaka".data(using: .utf8)!, to: RepositoryPath(string: "asia/japan/osaka.txt"))

        let commit2 = try await repository.publishWorkspace(workspace2, toBranch: "main", message: "Update nested files")

        // Diff commit2 against commit1
        let diffSession = await repository.session(commit: commit2)
        let changes = try await diffSession.diff(against: commit1)

        XCTAssertEqual(changes.count, 3)

        let modified = changes.filter { if case .modified = $0.type { return true }; return false }
        let added = changes.filter { if case .added = $0.type { return true }; return false }
        let deleted = changes.filter { if case .deleted = $0.type { return true }; return false }

        XCTAssertEqual(modified.count, 1)
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(deleted.count, 1)

        XCTAssertTrue(modified.contains { $0.path == RepositoryPath(string: "asia/japan/tokyo.txt") })
        XCTAssertTrue(added.contains { $0.path == RepositoryPath(string: "asia/japan/osaka.txt") })
        XCTAssertTrue(deleted.contains { $0.path == RepositoryPath(string: "asia/japan/kyoto.txt") })
    }

    func testDiffWithNewDirectory() async throws {
        // Create commit with new directory
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.writeFile("Beijing".data(using: .utf8)!, to: RepositoryPath(string: "asia/china/beijing.txt"))
        try await session.writeFile("Shanghai".data(using: .utf8)!, to: RepositoryPath(string: "asia/china/shanghai.txt"))

        let commit2 = try await repository.publishWorkspace(workspace, toBranch: "main", message: "Add china directory")

        // Diff commit2 against commit1
        let diffSession = await repository.session(commit: commit2)
        let changes = try await diffSession.diff(against: CommitID(value: "@1000"))

        XCTAssertEqual(changes.count, 2)

        let added = changes.filter { if case .added = $0.type { return true }; return false }
        XCTAssertEqual(added.count, 2)
        XCTAssertTrue(added.contains { $0.path == RepositoryPath(string: "asia/china/beijing.txt") })
        XCTAssertTrue(added.contains { $0.path == RepositoryPath(string: "asia/china/shanghai.txt") })
    }

    func testDiffWithDeletedDirectory() async throws {
        // Create base commit with directory
        let workspace1 = try await repository.createWorkspace(fromBranch: "main")
        let session1 = await repository.session(workspace: workspace1)

        try await session1.writeFile("File1".data(using: .utf8)!, to: RepositoryPath(string: "dir/file1.txt"))
        try await session1.writeFile("File2".data(using: .utf8)!, to: RepositoryPath(string: "dir/file2.txt"))

        let commit1 = try await repository.publishWorkspace(workspace1, toBranch: "main", message: "Add directory")

        // Create commit that deletes directory
        let workspace2 = try await repository.createWorkspace(fromBranch: "main")
        let session2 = await repository.session(workspace: workspace2)

        try await session2.deleteFile(at: RepositoryPath(string: "dir/file1.txt"))
        try await session2.deleteFile(at: RepositoryPath(string: "dir/file2.txt"))

        let commit2 = try await repository.publishWorkspace(workspace2, toBranch: "main", message: "Delete directory")

        // Diff commit2 against commit1
        let diffSession = await repository.session(commit: commit2)
        let changes = try await diffSession.diff(against: commit1)

        XCTAssertEqual(changes.count, 2)

        let deleted = changes.filter { if case .deleted = $0.type { return true }; return false }
        XCTAssertEqual(deleted.count, 2)
        XCTAssertTrue(deleted.contains { $0.path == RepositoryPath(string: "dir/file1.txt") })
        XCTAssertTrue(deleted.contains { $0.path == RepositoryPath(string: "dir/file2.txt") })
    }

    // MARK: - Edge Cases

    func testDiffReverseOrder() async throws {
        // Create second commit
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.writeFile("New file".data(using: .utf8)!, to: RepositoryPath(string: "new.txt"))

        let commit2 = try await repository.publishWorkspace(workspace, toBranch: "main", message: "Add new file")

        // Diff old commit against new commit (reverse order)
        let diffSession = await repository.session(commit: CommitID(value: "@1000"))
        let changes = try await diffSession.diff(against: commit2)

        // Old commit vs new commit: new.txt was added in commit2, so it's deleted when going back
        XCTAssertEqual(changes.count, 1)

        if case .deleted = changes[0].type {
            XCTAssertEqual(changes[0].path, RepositoryPath(string: "new.txt"))
        } else {
            XCTFail("Expected deletion when comparing old vs new")
        }
    }

    func testDiffFileToDirectoryConversion() async throws {
        // Create base with file
        let workspace1 = try await repository.createWorkspace(fromBranch: "main")
        let session1 = await repository.session(workspace: workspace1)

        try await session1.writeFile("File content".data(using: .utf8)!, to: RepositoryPath(string: "item"))

        let commit1 = try await repository.publishWorkspace(workspace1, toBranch: "main", message: "Add file")

        // Create commit that replaces file with directory
        let workspace2 = try await repository.createWorkspace(fromBranch: "main")
        let session2 = await repository.session(workspace: workspace2)

        try await session2.deleteFile(at: RepositoryPath(string: "item"))
        try await session2.writeFile("Nested".data(using: .utf8)!, to: RepositoryPath(string: "item/nested.txt"))

        let commit2 = try await repository.publishWorkspace(workspace2, toBranch: "main", message: "Convert to directory")

        // Diff
        let diffSession = await repository.session(commit: commit2)
        let changes = try await diffSession.diff(against: commit1)

        // Should show deletion of file + addition of file (type change)
        XCTAssertEqual(changes.count, 2)

        let deleted = changes.filter { if case .deleted = $0.type { return true }; return false }
        let added = changes.filter { if case .added = $0.type { return true }; return false }

        XCTAssertEqual(deleted.count, 1)
        XCTAssertEqual(added.count, 1)

        // The added file should be the nested one
        XCTAssertTrue(added.contains { $0.path == RepositoryPath(string: "item/nested.txt") })
        XCTAssertTrue(deleted.contains { $0.path == RepositoryPath(string: "item") })
    }
}
