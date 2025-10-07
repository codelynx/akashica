import XCTest
@testable import Akashica
@testable import AkashicaStorage

final class WorkflowIntegrationTests: XCTestCase {
    var tempDir: URL!
    var storage: LocalStorageAdapter!
    var repository: AkashicaRepository!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashica_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storage = LocalStorageAdapter(rootPath: tempDir)
        repository = AkashicaRepository(storage: storage)

        // Create initial commit with a file
        try await createInitialCommit()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helper Methods

    private func createInitialCommit() async throws {
        let commitID = CommitID(value: "@1001")

        // Create a simple manifest with one file
        let content = "Initial content".data(using: .utf8)!
        let hash = try await storage.writeObject(data: content)

        // Manifest format: {hash}:{size}:{name}
        let manifestEntry = "\(hash.value):\(content.count):README.md"
        let manifestData = manifestEntry.data(using: .utf8)!

        try await storage.writeRootManifest(commit: commitID, data: manifestData)

        // Create main branch pointing to this commit
        try await storage.updateBranch(name: "main", expectedCurrent: nil, newCommit: commitID)
    }

    // MARK: - Workspace Creation Tests

    func testCreateWorkspaceFromCommit() async throws {
        let commitID = CommitID(value: "@1001")
        let workspace = try await repository.createWorkspace(from: commitID)

        // Verify workspace ID format
        XCTAssertEqual(workspace.baseCommit, commitID)
        XCTAssertEqual(workspace.workspaceSuffix.count, 4, "Workspace suffix should be 4 characters")

        // Verify workspace metadata was created
        let metadata = try await storage.readWorkspaceMetadata(workspace: workspace)
        XCTAssertEqual(metadata.base, commitID)
    }

    func testCreateWorkspaceFromBranch() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")

        // Verify workspace points to branch head
        XCTAssertEqual(workspace.baseCommit.value, "@1001")
    }

    // MARK: - File Read/Write Tests

    func testWriteAndReadFileInWorkspace() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Write a new file
        let content = "Test file content".data(using: .utf8)!
        try await session.writeFile(content, to: RepositoryPath(string: "test.txt"))

        // Read it back
        let readData = try await session.readFile(at: RepositoryPath(string: "test.txt"))
        XCTAssertEqual(readData, content)
    }

    func testReadFileFromBaseCommit() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Should be able to read file from base commit
        let data = try await session.readFile(at: RepositoryPath(string: "README.md"))
        let content = String(data: data, encoding: .utf8)
        XCTAssertEqual(content, "Initial content")
    }

    func testDeleteFile() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Write a file
        let content = "Temporary file".data(using: .utf8)!
        try await session.writeFile(content, to: RepositoryPath(string: "temp.txt"))

        // Verify it exists
        let exists = try await session.fileExists(at: RepositoryPath(string: "temp.txt"))
        XCTAssertTrue(exists)

        // Delete it
        try await session.deleteFile(at: RepositoryPath(string: "temp.txt"))

        // Verify it's gone
        do {
            _ = try await session.readFile(at: RepositoryPath(string: "temp.txt"))
            XCTFail("Should have thrown fileNotFound")
        } catch AkashicaError.fileNotFound {
            // Expected
        }
    }

    // MARK: - Status Detection Tests

    func testStatusDetectsAddedFiles() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Add new files
        try await session.writeFile("File 1".data(using: .utf8)!, to: RepositoryPath(string: "new1.txt"))
        try await session.writeFile("File 2".data(using: .utf8)!, to: RepositoryPath(string: "new2.txt"))

        let status = try await session.status()

        XCTAssertEqual(status.added.count, 2)
        XCTAssertTrue(status.added.contains(RepositoryPath(string: "new1.txt")))
        XCTAssertTrue(status.added.contains(RepositoryPath(string: "new2.txt")))
        XCTAssertEqual(status.modified.count, 0)
        XCTAssertEqual(status.deleted.count, 0)
    }

    func testStatusDetectsModifiedFiles() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Modify existing file from base commit
        let newContent = "Modified content".data(using: .utf8)!
        try await session.writeFile(newContent, to: RepositoryPath(string: "README.md"))

        let status = try await session.status()

        XCTAssertEqual(status.modified.count, 1)
        XCTAssertTrue(status.modified.contains(RepositoryPath(string: "README.md")))
        XCTAssertEqual(status.added.count, 0)
        XCTAssertEqual(status.deleted.count, 0)
    }

    func testStatusDetectsDeletedFiles() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Delete file from base commit
        try await session.deleteFile(at: RepositoryPath(string: "README.md"))

        let status = try await session.status()

        XCTAssertEqual(status.deleted.count, 1)
        XCTAssertTrue(status.deleted.contains(RepositoryPath(string: "README.md")))
        XCTAssertEqual(status.added.count, 0)
        XCTAssertEqual(status.modified.count, 0)
    }

    // MARK: - Publish Workflow Tests

    func testPublishWorkflowEndToEnd() async throws {
        // 1. Create workspace
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // 2. Make changes
        try await session.writeFile("New file".data(using: .utf8)!, to: RepositoryPath(string: "new.txt"))
        try await session.writeFile("Updated README".data(using: .utf8)!, to: RepositoryPath(string: "README.md"))

        // 3. Verify status before publish
        let status = try await session.status()
        XCTAssertEqual(status.added.count, 1)
        XCTAssertEqual(status.modified.count, 1)

        // 4. Publish workspace
        let newCommitID = try await repository.publishWorkspace(
            workspace,
            toBranch: "main",
            message: "Add new file and update README"
        )

        // 5. Verify new commit exists
        XCTAssertNotEqual(newCommitID.value, "@1001")

        // 6. Verify branch now points to new commit
        let branchHead = try await repository.currentCommit(branch: "main")
        XCTAssertEqual(branchHead, newCommitID)

        // 7. Read files from new commit
        let newSession = await repository.session(commit: newCommitID)
        let newFileData = try await newSession.readFile(at: RepositoryPath(string: "new.txt"))
        XCTAssertEqual(String(data: newFileData, encoding: .utf8), "New file")

        let readmeData = try await newSession.readFile(at: RepositoryPath(string: "README.md"))
        XCTAssertEqual(String(data: readmeData, encoding: .utf8), "Updated README")
    }

    func testPublishDeletesWorkspace() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Make a change
        try await session.writeFile("Test".data(using: .utf8)!, to: RepositoryPath(string: "test.txt"))

        // Publish
        _ = try await repository.publishWorkspace(workspace, toBranch: "main", message: "Test")

        // Verify workspace is deleted
        let exists = try await storage.workspaceExists(workspace: workspace)
        XCTAssertFalse(exists)
    }

    // MARK: - Session Independence Tests

    func testMultipleSessionsAreIndependent() async throws {
        let workspace1 = try await repository.createWorkspace(fromBranch: "main")
        let workspace2 = try await repository.createWorkspace(fromBranch: "main")

        let session1 = await repository.session(workspace: workspace1)
        let session2 = await repository.session(workspace: workspace2)

        // Write different content in each workspace
        try await session1.writeFile("Content A".data(using: .utf8)!, to: RepositoryPath(string: "file.txt"))
        try await session2.writeFile("Content B".data(using: .utf8)!, to: RepositoryPath(string: "file.txt"))

        // Verify each workspace has its own content
        let data1 = try await session1.readFile(at: RepositoryPath(string: "file.txt"))
        let data2 = try await session2.readFile(at: RepositoryPath(string: "file.txt"))

        XCTAssertEqual(String(data: data1, encoding: .utf8), "Content A")
        XCTAssertEqual(String(data: data2, encoding: .utf8), "Content B")
    }

    func testCommitSessionIsReadOnly() async throws {
        let session = await repository.session(commit: CommitID(value: "@1001"))

        let isReadOnly = await session.isReadOnly
        XCTAssertTrue(isReadOnly)

        // Verify write operations throw
        do {
            try await session.writeFile("Test".data(using: .utf8)!, to: RepositoryPath(string: "test.txt"))
            XCTFail("Should have thrown sessionReadOnly")
        } catch AkashicaError.sessionReadOnly {
            // Expected
        }
    }

    // MARK: - Error Handling Tests

    func testReadNonexistentFile() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        do {
            _ = try await session.readFile(at: RepositoryPath(string: "nonexistent.txt"))
            XCTFail("Should have thrown fileNotFound")
        } catch AkashicaError.fileNotFound {
            // Expected
        }
    }

    func testFileExistsCheck() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // File from base commit exists
        let existsInBase = try await session.fileExists(at: RepositoryPath(string: "README.md"))
        XCTAssertTrue(existsInBase)

        // New file doesn't exist yet
        let existsNew = try await session.fileExists(at: RepositoryPath(string: "new.txt"))
        XCTAssertFalse(existsNew)

        // Write new file
        try await session.writeFile("Test".data(using: .utf8)!, to: RepositoryPath(string: "new.txt"))

        // Now it exists
        let existsAfterWrite = try await session.fileExists(at: RepositoryPath(string: "new.txt"))
        XCTAssertTrue(existsAfterWrite)
    }
}
