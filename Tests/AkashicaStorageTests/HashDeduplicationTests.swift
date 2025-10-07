import XCTest
@testable import Akashica
@testable import AkashicaStorage

final class HashDeduplicationTests: XCTestCase {
    var tempDir: URL!
    var storage: LocalStorageAdapter!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashica_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        storage = LocalStorageAdapter(rootPath: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testHashDeduplication() async throws {
        // Write same content twice
        let content = "Test content for deduplication".data(using: .utf8)!

        let hash1 = try await storage.writeObject(data: content)
        let hash2 = try await storage.writeObject(data: content)

        // Hashes should match (same content = same hash)
        XCTAssertEqual(hash1.value, hash2.value, "Same content should produce same hash")

        // Verify hash is 64 characters (SHA-256)
        XCTAssertEqual(hash1.value.count, 64, "SHA-256 hash should be 64 characters")

        // Verify we can read it back
        let readData = try await storage.readObject(hash: hash1)
        XCTAssertEqual(readData, content, "Read data should match written data")
    }

    func testDifferentContentProducesDifferentHashes() async throws {
        let content1 = "Content A".data(using: .utf8)!
        let content2 = "Content B".data(using: .utf8)!

        let hash1 = try await storage.writeObject(data: content1)
        let hash2 = try await storage.writeObject(data: content2)

        XCTAssertNotEqual(hash1.value, hash2.value, "Different content should produce different hashes")
    }

    func testManifestHashing() async throws {
        let manifest = "hash1:1024:file1.txt\nhash2:2048:file2.txt".data(using: .utf8)!

        let hash = try await storage.writeManifest(data: manifest)

        // Verify manifest uses same hashing
        XCTAssertEqual(hash.value.count, 64, "Manifest hash should also be 64 characters")

        // Verify we can read it back
        let readData = try await storage.readManifest(hash: hash)
        XCTAssertEqual(readData, manifest, "Read manifest should match written manifest")
    }
}
