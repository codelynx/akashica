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

        // Write commit metadata (needed for ancestry checks)
        let metadata = CommitMetadata(
            message: "Initial commit",
            author: "test",
            timestamp: Date(),
            parent: nil
        )
        try await storage.writeCommitMetadata(commit: commitID, metadata: metadata)

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

    // MARK: - Branch Reset Tests

    func testResetBranchToAncestor() async throws {
        // Create commit chain: @1001 -> @1002 -> @1003
        let commit1002 = try await createCommit(parent: CommitID(value: "@1001"), message: "Second commit")
        let commit1003 = try await createCommit(parent: commit1002, message: "Third commit")

        // Verify branch points to @1003
        let head = try await repository.currentCommit(branch: "main")
        XCTAssertEqual(head, commit1003)

        // Reset to @1002
        try await repository.resetBranch(name: "main", to: commit1002)

        // Verify branch now points to @1002
        let newHead = try await repository.currentCommit(branch: "main")
        XCTAssertEqual(newHead, commit1002)
    }

    func testResetBranchToNonAncestorFails() async throws {
        // Create commit chain: @1001 -> @1002 -> @1003
        let commit1002 = try await createCommit(parent: CommitID(value: "@1001"), message: "Second commit")
        _ = try await createCommit(parent: commit1002, message: "Third commit")

        // Create unrelated commit @2001
        let unrelatedCommit = CommitID(value: "@2001")
        let content = "Unrelated content".data(using: .utf8)!
        let hash = try await storage.writeObject(data: content)
        let manifestEntry = "\(hash.value):\(content.count):unrelated.txt"
        let manifestData = manifestEntry.data(using: .utf8)!
        try await storage.writeRootManifest(commit: unrelatedCommit, data: manifestData)

        let metadata = CommitMetadata(
            message: "Unrelated commit",
            author: "test",
            timestamp: Date(),
            parent: nil
        )
        try await storage.writeCommitMetadata(commit: unrelatedCommit, metadata: metadata)

        // Try to reset to unrelated commit - should fail
        do {
            try await repository.resetBranch(name: "main", to: unrelatedCommit)
            XCTFail("Should have thrown nonAncestorReset")
        } catch AkashicaError.nonAncestorReset(let branch, _, let target) {
            XCTAssertEqual(branch, "main")
            XCTAssertEqual(target, unrelatedCommit)
        }
    }

    func testResetBranchWithForce() async throws {
        // Create commit chain: @1001 -> @1002 -> @1003
        let commit1002 = try await createCommit(parent: CommitID(value: "@1001"), message: "Second commit")
        _ = try await createCommit(parent: commit1002, message: "Third commit")

        // Create unrelated commit @2001
        let unrelatedCommit = CommitID(value: "@2001")
        let content = "Unrelated content".data(using: .utf8)!
        let hash = try await storage.writeObject(data: content)
        let manifestEntry = "\(hash.value):\(content.count):unrelated.txt"
        let manifestData = manifestEntry.data(using: .utf8)!
        try await storage.writeRootManifest(commit: unrelatedCommit, data: manifestData)

        let metadata = CommitMetadata(
            message: "Unrelated commit",
            author: "test",
            timestamp: Date(),
            parent: nil
        )
        try await storage.writeCommitMetadata(commit: unrelatedCommit, metadata: metadata)

        // Reset with --force should succeed
        try await repository.resetBranch(name: "main", to: unrelatedCommit, force: true)

        // Verify branch now points to unrelated commit
        let newHead = try await repository.currentCommit(branch: "main")
        XCTAssertEqual(newHead, unrelatedCommit)
    }

    func testResetBranchToSameCommitIsNoop() async throws {
        let currentHead = try await repository.currentCommit(branch: "main")

        // Reset to current head (should be no-op)
        try await repository.resetBranch(name: "main", to: currentHead)

        // Verify branch still points to same commit
        let newHead = try await repository.currentCommit(branch: "main")
        XCTAssertEqual(newHead, currentHead)
    }

    func testResetBranchToNonexistentCommitFails() async throws {
        let nonexistentCommit = CommitID(value: "@9999")

        // Try to reset to nonexistent commit - should fail even with --force
        do {
            try await repository.resetBranch(name: "main", to: nonexistentCommit, force: true)
            XCTFail("Should have thrown commitNotFound")
        } catch AkashicaError.commitNotFound {
            // Expected
        }

        // Verify branch still points to original commit
        let head = try await repository.currentCommit(branch: "main")
        XCTAssertEqual(head.value, "@1001")
    }

    func testIsAncestor() async throws {
        // Create commit chain: @1001 -> @1002 -> @1003
        let commit1002 = try await createCommit(parent: CommitID(value: "@1001"), message: "Second commit")
        let commit1003 = try await createCommit(parent: commit1002, message: "Third commit")

        // @1001 is ancestor of @1003
        let isAncestor1 = try await repository.isAncestor(CommitID(value: "@1001"), of: commit1003)
        XCTAssertTrue(isAncestor1)

        // @1002 is ancestor of @1003
        let isAncestor2 = try await repository.isAncestor(commit1002, of: commit1003)
        XCTAssertTrue(isAncestor2)

        // @1003 is ancestor of @1003 (self)
        let isAncestor3 = try await repository.isAncestor(commit1003, of: commit1003)
        XCTAssertTrue(isAncestor3)

        // @1003 is NOT ancestor of @1002
        let isAncestor4 = try await repository.isAncestor(commit1003, of: commit1002)
        XCTAssertFalse(isAncestor4)

        // Create unrelated commit
        let unrelated = CommitID(value: "@2001")
        let content = "Unrelated".data(using: .utf8)!
        let hash = try await storage.writeObject(data: content)
        let manifestEntry = "\(hash.value):\(content.count):file.txt"
        let manifestData = manifestEntry.data(using: .utf8)!
        try await storage.writeRootManifest(commit: unrelated, data: manifestData)

        let metadata = CommitMetadata(
            message: "Unrelated",
            author: "test",
            timestamp: Date(),
            parent: nil
        )
        try await storage.writeCommitMetadata(commit: unrelated, metadata: metadata)

        // Unrelated commit is NOT ancestor
        let isAncestor5 = try await repository.isAncestor(unrelated, of: commit1003)
        XCTAssertFalse(isAncestor5)
    }

    func testCommitsBetween() async throws {
        // Create commit chain: @1001 -> @1002 -> @1003 -> @1004
        let commit1002 = try await createCommit(parent: CommitID(value: "@1001"), message: "Second")
        let commit1003 = try await createCommit(parent: commit1002, message: "Third")
        let commit1004 = try await createCommit(parent: commit1003, message: "Fourth")

        // Get commits between @1001 and @1004
        let commits = try await repository.commitsBetween(from: CommitID(value: "@1001"), to: commit1004)

        // Should return [@1004, @1003, @1002] (reverse chronological, excluding @1001)
        XCTAssertEqual(commits.count, 3)
        XCTAssertEqual(commits[0].commit, commit1004)
        XCTAssertEqual(commits[0].metadata.message, "Fourth")
        XCTAssertEqual(commits[1].commit, commit1003)
        XCTAssertEqual(commits[1].metadata.message, "Third")
        XCTAssertEqual(commits[2].commit, commit1002)
        XCTAssertEqual(commits[2].metadata.message, "Second")

        // Get commits between @1002 and @1004
        let commits2 = try await repository.commitsBetween(from: commit1002, to: commit1004)
        XCTAssertEqual(commits2.count, 2)
        XCTAssertEqual(commits2[0].commit, commit1004)
        XCTAssertEqual(commits2[1].commit, commit1003)

        // Same commit returns empty
        let commits3 = try await repository.commitsBetween(from: commit1004, to: commit1004)
        XCTAssertEqual(commits3.count, 0)
    }

    // MARK: - Branch Reset Integration Tests

    func testResetBranchIntegration() async throws {
        // Create a commit chain: @1001 -> @1002 -> @1003
        let commit1002 = try await createCommit(parent: CommitID(value: "@1001"), message: "Second")
        let commit1003 = try await createCommit(parent: commit1002, message: "Third")

        // Verify main points to @1003
        let initialHead = try await repository.currentCommit(branch: "main")
        XCTAssertEqual(initialHead, commit1003)

        // Reset back to @1002
        try await repository.resetBranch(name: "main", to: commit1002)

        // Verify branch pointer updated
        let afterReset = try await repository.currentCommit(branch: "main")
        XCTAssertEqual(afterReset, commit1002)

        // Verify we can still read files from @1002
        let session = try await repository.session(branch: "main")
        let fileExists = try await session.fileExists(at: RepositoryPath(string: "Second.txt"))
        XCTAssertTrue(fileExists)

        // Verify @1003 file is NOT accessible (orphaned)
        let orphanedExists = try await session.fileExists(at: RepositoryPath(string: "Third.txt"))
        XCTAssertFalse(orphanedExists)
    }

    // MARK: - Helper for Branch Reset Tests

    private func createCommit(parent: CommitID, message: String) async throws -> CommitID {
        // Create workspace from parent
        let workspace = try await repository.createWorkspace(from: parent)
        let session = await repository.session(workspace: workspace)

        // Make a change (write a file with commit-specific content)
        let content = "\(message) content".data(using: .utf8)!
        try await session.writeFile(content, to: RepositoryPath(string: "\(message).txt"))

        // Publish to create new commit
        let newCommit = try await repository.publishWorkspace(
            workspace,
            toBranch: "main",
            message: message,
            author: "test"
        )

        return newCommit
    }
}
