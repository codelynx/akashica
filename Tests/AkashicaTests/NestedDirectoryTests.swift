import XCTest
@testable import Akashica
@testable import AkashicaStorage

final class NestedDirectoryTests: XCTestCase {
    var tempDir: URL!
    var storage: LocalStorageAdapter!
    var repository: AkashicaRepository!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashica-nested-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        storage = LocalStorageAdapter(rootPath: tempDir)
        repository = AkashicaRepository(storage: storage)

        // Create initial commit with nested directory structure
        let initialCommit = CommitID(value: "@1000")

        // Create asia/japan/ manifest with tokyo.txt file
        let tokyoData = "Tokyo content".data(using: .utf8)!
        let tokyoHash = try await storage.writeObject(data: tokyoData)
        let japanManifest = "\(tokyoHash.value):\(tokyoData.count):tokyo.txt".data(using: .utf8)!
        let japanHash = try await storage.writeManifest(data: japanManifest)

        // Create asia/ manifest with japan/ directory
        let asiaManifest = "\(japanHash.value):\(japanManifest.count):japan/".data(using: .utf8)!
        let asiaHash = try await storage.writeManifest(data: asiaManifest)

        // Create root manifest with asia/ directory
        let rootManifest = "\(asiaHash.value):\(asiaManifest.count):asia/".data(using: .utf8)!
        try await storage.writeRootManifest(commit: initialCommit, data: rootManifest)

        let initialMetadata = CommitMetadata(
            message: "Initial commit with nested directories",
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

    // MARK: - Nested File Operations

    func testWriteFileToNestedDirectory() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        let newContent = "Kyoto content".data(using: .utf8)!
        try await session.writeFile(newContent, to: RepositoryPath(string: "asia/japan/kyoto.txt"))

        // Verify file was written
        let readBack = try await session.readFile(at: RepositoryPath(string: "asia/japan/kyoto.txt"))
        XCTAssertEqual(readBack, newContent)
    }

    func testWriteFileToDeepNestedDirectory() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        let content = "Shibuya content".data(using: .utf8)!
        try await session.writeFile(content, to: RepositoryPath(string: "asia/japan/tokyo/shibuya.txt"))

        let readBack = try await session.readFile(at: RepositoryPath(string: "asia/japan/tokyo/shibuya.txt"))
        XCTAssertEqual(readBack, content)
    }

    func testModifyFileInNestedDirectory() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Modify existing file
        let newContent = "Updated Tokyo content".data(using: .utf8)!
        try await session.writeFile(newContent, to: RepositoryPath(string: "asia/japan/tokyo.txt"))

        let readBack = try await session.readFile(at: RepositoryPath(string: "asia/japan/tokyo.txt"))
        XCTAssertEqual(readBack, newContent)
    }

    func testDeleteFileInNestedDirectory() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.deleteFile(at: RepositoryPath(string: "asia/japan/tokyo.txt"))

        let exists = try await session.fileExists(at: RepositoryPath(string: "asia/japan/tokyo.txt"))
        XCTAssertFalse(exists)
    }

    // MARK: - Status Detection with Nested Directories

    func testStatusDetectsNestedFileAddition() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.writeFile("Kyoto".data(using: .utf8)!, to: RepositoryPath(string: "asia/japan/kyoto.txt"))

        let status = try await session.status()
        XCTAssertTrue(status.added.contains(RepositoryPath(string: "asia/japan/kyoto.txt")))
        XCTAssertTrue(status.modified.isEmpty)
        XCTAssertTrue(status.deleted.isEmpty)
    }

    func testStatusDetectsNestedFileModification() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.writeFile("Updated".data(using: .utf8)!, to: RepositoryPath(string: "asia/japan/tokyo.txt"))

        let status = try await session.status()
        XCTAssertTrue(status.modified.contains(RepositoryPath(string: "asia/japan/tokyo.txt")))
        XCTAssertTrue(status.added.isEmpty)
        XCTAssertTrue(status.deleted.isEmpty)
    }

    func testStatusDetectsNestedFileDeletion() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.deleteFile(at: RepositoryPath(string: "asia/japan/tokyo.txt"))

        let status = try await session.status()
        XCTAssertTrue(status.deleted.contains(RepositoryPath(string: "asia/japan/tokyo.txt")))
        XCTAssertTrue(status.added.isEmpty)
        XCTAssertTrue(status.modified.isEmpty)
    }

    // MARK: - Publish Workflow with Nested Directories

    func testPublishNestedDirectoryChanges() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Add new file in nested directory
        try await session.writeFile("Kyoto".data(using: .utf8)!, to: RepositoryPath(string: "asia/japan/kyoto.txt"))

        // Modify existing file
        try await session.writeFile("Updated Tokyo".data(using: .utf8)!, to: RepositoryPath(string: "asia/japan/tokyo.txt"))

        let newCommit = try await repository.publishWorkspace(
            workspace,
            toBranch: "main",
            message: "Update nested files"
        )

        // Verify changes persisted in new commit
        let newSession = await repository.session(commit: newCommit)
        let kyotoContent = try await newSession.readFile(at: RepositoryPath(string: "asia/japan/kyoto.txt"))
        XCTAssertEqual(String(data: kyotoContent, encoding: .utf8), "Kyoto")

        let tokyoContent = try await newSession.readFile(at: RepositoryPath(string: "asia/japan/tokyo.txt"))
        XCTAssertEqual(String(data: tokyoContent, encoding: .utf8), "Updated Tokyo")
    }

    func testPublishWithDeepNesting() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Create deeply nested structure
        try await session.writeFile("A".data(using: .utf8)!, to: RepositoryPath(string: "a/b/c/d/e.txt"))
        try await session.writeFile("F".data(using: .utf8)!, to: RepositoryPath(string: "a/b/c/d/f.txt"))

        let newCommit = try await repository.publishWorkspace(
            workspace,
            toBranch: "main",
            message: "Deep nesting test"
        )

        // Verify files exist in new commit
        let newSession = await repository.session(commit: newCommit)
        let eContent = try await newSession.readFile(at: RepositoryPath(string: "a/b/c/d/e.txt"))
        XCTAssertEqual(String(data: eContent, encoding: .utf8), "A")

        let fContent = try await newSession.readFile(at: RepositoryPath(string: "a/b/c/d/f.txt"))
        XCTAssertEqual(String(data: fContent, encoding: .utf8), "F")
    }

    // MARK: - Directory Listing with Nested Directories

    func testListNestedDirectory() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Add files to nested directory
        try await session.writeFile("Kyoto".data(using: .utf8)!, to: RepositoryPath(string: "asia/japan/kyoto.txt"))
        try await session.writeFile("Osaka".data(using: .utf8)!, to: RepositoryPath(string: "asia/japan/osaka.txt"))

        let entries = try await session.listDirectory(at: RepositoryPath(string: "asia/japan"))

        XCTAssertEqual(entries.count, 3) // tokyo.txt + kyoto.txt + osaka.txt
        XCTAssertTrue(entries.contains { $0.name == "tokyo.txt" })
        XCTAssertTrue(entries.contains { $0.name == "kyoto.txt" })
        XCTAssertTrue(entries.contains { $0.name == "osaka.txt" })
    }

    func testListDirectoryAfterNestedDeletion() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        try await session.deleteFile(at: RepositoryPath(string: "asia/japan/tokyo.txt"))

        let entries = try await session.listDirectory(at: RepositoryPath(string: "asia/japan"))

        XCTAssertEqual(entries.count, 0)
        XCTAssertFalse(entries.contains { $0.name == "tokyo.txt" })
    }

    // MARK: - Manifest Update Correctness

    func testManifestUpdatesPropagateToRoot() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Write file in deeply nested directory
        try await session.writeFile("Test".data(using: .utf8)!, to: RepositoryPath(string: "asia/japan/kyoto.txt"))

        // Verify workspace manifests exist at each level
        let rootManifest = try await storage.readWorkspaceManifest(
            workspace: workspace,
            path: RepositoryPath(string: "")
        )
        XCTAssertNotNil(rootManifest)

        let asiaManifest = try await storage.readWorkspaceManifest(
            workspace: workspace,
            path: RepositoryPath(string: "asia")
        )
        XCTAssertNotNil(asiaManifest)

        let japanManifest = try await storage.readWorkspaceManifest(
            workspace: workspace,
            path: RepositoryPath(string: "asia/japan")
        )
        XCTAssertNotNil(japanManifest)
    }

    func testMultipleNestedChangesInDifferentDirectories() async throws {
        let workspace = try await repository.createWorkspace(fromBranch: "main")
        let session = await repository.session(workspace: workspace)

        // Make changes in different nested directories
        try await session.writeFile("China".data(using: .utf8)!, to: RepositoryPath(string: "asia/china/beijing.txt"))
        try await session.writeFile("Korea".data(using: .utf8)!, to: RepositoryPath(string: "asia/korea/seoul.txt"))
        try await session.writeFile("Kyoto".data(using: .utf8)!, to: RepositoryPath(string: "asia/japan/kyoto.txt"))

        let status = try await session.status()
        XCTAssertEqual(status.added.count, 3)
        XCTAssertTrue(status.added.contains(RepositoryPath(string: "asia/china/beijing.txt")))
        XCTAssertTrue(status.added.contains(RepositoryPath(string: "asia/korea/seoul.txt")))
        XCTAssertTrue(status.added.contains(RepositoryPath(string: "asia/japan/kyoto.txt")))

        // Publish and verify
        let newCommit = try await repository.publishWorkspace(workspace, toBranch: "main", message: "Multiple nested changes")

        let newSession = await repository.session(commit: newCommit)
        let beijingExists = try await newSession.fileExists(at: RepositoryPath(string: "asia/china/beijing.txt"))
        let seoulExists = try await newSession.fileExists(at: RepositoryPath(string: "asia/korea/seoul.txt"))
        let kyotoExists = try await newSession.fileExists(at: RepositoryPath(string: "asia/japan/kyoto.txt"))

        XCTAssertTrue(beijingExists)
        XCTAssertTrue(seoulExists)
        XCTAssertTrue(kyotoExists)
    }
}
