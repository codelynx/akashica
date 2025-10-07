import XCTest
@testable import Akashica

final class ModelEqualityTests: XCTestCase {

    // MARK: - CommitID Equality Tests

    func testCommitIDEquality() {
        let id1 = CommitID(value: "@1002")
        let id2 = CommitID(value: "@1002")
        let id3 = CommitID(value: "@1003")

        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, id3)
    }

    func testCommitIDHashValue() {
        let id1 = CommitID(value: "@1002")
        let id2 = CommitID(value: "@1002")

        XCTAssertEqual(id1.hashValue, id2.hashValue)
    }

    func testCommitIDInSet() {
        let id1 = CommitID(value: "@1002")
        let id2 = CommitID(value: "@1002")
        let id3 = CommitID(value: "@1003")

        var set: Set<CommitID> = [id1, id2, id3]
        XCTAssertEqual(set.count, 2) // id1 and id2 are equal
        XCTAssertTrue(set.contains(id1))
        XCTAssertTrue(set.contains(id3))
    }

    func testCommitIDInDictionary() {
        let id1 = CommitID(value: "@1002")
        let id2 = CommitID(value: "@1003")

        var dict: [CommitID: String] = [:]
        dict[id1] = "First"
        dict[id2] = "Second"

        XCTAssertEqual(dict[id1], "First")
        XCTAssertEqual(dict[id2], "Second")
        XCTAssertEqual(dict.count, 2)
    }

    // MARK: - WorkspaceID Equality Tests

    func testWorkspaceIDEquality() {
        let workspace1 = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3")
        let workspace2 = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3")
        let workspace3 = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "c3d4")

        XCTAssertEqual(workspace1, workspace2)
        XCTAssertNotEqual(workspace1, workspace3)
    }

    func testWorkspaceIDDifferentBaseCommit() {
        let workspace1 = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3")
        let workspace2 = WorkspaceID(baseCommit: CommitID(value: "@1003"), workspaceSuffix: "a1b3")

        XCTAssertNotEqual(workspace1, workspace2)
    }

    func testWorkspaceIDHashValue() {
        let workspace1 = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3")
        let workspace2 = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3")

        XCTAssertEqual(workspace1.hashValue, workspace2.hashValue)
    }

    func testWorkspaceIDInSet() {
        let workspace1 = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3")
        let workspace2 = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3")
        let workspace3 = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "c3d4")

        var set: Set<WorkspaceID> = [workspace1, workspace2, workspace3]
        XCTAssertEqual(set.count, 2) // workspace1 and workspace2 are equal
    }

    // MARK: - ChangesetRef Equality Tests

    func testChangesetRefEqualityCommitCase() {
        let ref1 = ChangesetRef.commit(CommitID(value: "@1002"))
        let ref2 = ChangesetRef.commit(CommitID(value: "@1002"))
        let ref3 = ChangesetRef.commit(CommitID(value: "@1003"))

        XCTAssertEqual(ref1, ref2)
        XCTAssertNotEqual(ref1, ref3)
    }

    func testChangesetRefEqualityWorkspaceCase() {
        let workspace1 = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3")
        let workspace2 = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3")
        let workspace3 = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "c3d4")

        let ref1 = ChangesetRef.workspace(workspace1)
        let ref2 = ChangesetRef.workspace(workspace2)
        let ref3 = ChangesetRef.workspace(workspace3)

        XCTAssertEqual(ref1, ref2)
        XCTAssertNotEqual(ref1, ref3)
    }

    func testChangesetRefEqualityMixedCases() {
        let commitRef = ChangesetRef.commit(CommitID(value: "@1002"))
        let workspaceRef = ChangesetRef.workspace(WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3"))

        XCTAssertNotEqual(commitRef, workspaceRef)
    }

    func testChangesetRefHashValue() {
        let ref1 = ChangesetRef.commit(CommitID(value: "@1002"))
        let ref2 = ChangesetRef.commit(CommitID(value: "@1002"))

        XCTAssertEqual(ref1.hashValue, ref2.hashValue)
    }

    func testChangesetRefInSet() {
        let ref1 = ChangesetRef.commit(CommitID(value: "@1002"))
        let ref2 = ChangesetRef.commit(CommitID(value: "@1002"))
        let ref3 = ChangesetRef.workspace(WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3"))

        var set: Set<ChangesetRef> = [ref1, ref2, ref3]
        XCTAssertEqual(set.count, 2) // ref1 and ref2 are equal
    }

    // MARK: - DirectoryEntry Equality Tests

    func testDirectoryEntryEquality() {
        let hash1 = ContentHash(data: "test1".data(using: .utf8)!)
        let hash2 = ContentHash(data: "test1".data(using: .utf8)!)
        let hash3 = ContentHash(data: "test2".data(using: .utf8)!)

        let entry1 = DirectoryEntry(name: "file.txt", type: .file, size: 100, hash: hash1)
        let entry2 = DirectoryEntry(name: "file.txt", type: .file, size: 100, hash: hash2)
        let entry3 = DirectoryEntry(name: "file.txt", type: .file, size: 100, hash: hash3)

        XCTAssertEqual(entry1, entry2)
        XCTAssertNotEqual(entry1, entry3)
    }

    func testDirectoryEntryDifferentNames() {
        let hash = ContentHash(data: "test".data(using: .utf8)!)
        let entry1 = DirectoryEntry(name: "file1.txt", type: .file, size: 100, hash: hash)
        let entry2 = DirectoryEntry(name: "file2.txt", type: .file, size: 100, hash: hash)

        XCTAssertNotEqual(entry1, entry2)
    }

    func testDirectoryEntryDifferentTypes() {
        let hash = ContentHash(data: "test".data(using: .utf8)!)
        let entry1 = DirectoryEntry(name: "item", type: .file, size: 100, hash: hash)
        let entry2 = DirectoryEntry(name: "item", type: .directory, size: 100, hash: hash)

        XCTAssertNotEqual(entry1, entry2)
    }

    func testDirectoryEntryDifferentSizes() {
        let hash = ContentHash(data: "test".data(using: .utf8)!)
        let entry1 = DirectoryEntry(name: "file.txt", type: .file, size: 100, hash: hash)
        let entry2 = DirectoryEntry(name: "file.txt", type: .file, size: 200, hash: hash)

        XCTAssertNotEqual(entry1, entry2)
    }

    func testDirectoryEntryHashValue() {
        let hash = ContentHash(data: "test".data(using: .utf8)!)
        let entry1 = DirectoryEntry(name: "file.txt", type: .file, size: 100, hash: hash)
        let entry2 = DirectoryEntry(name: "file.txt", type: .file, size: 100, hash: hash)

        XCTAssertEqual(entry1.hashValue, entry2.hashValue)
    }

    func testDirectoryEntryInSet() {
        let hash1 = ContentHash(data: "test1".data(using: .utf8)!)
        let hash2 = ContentHash(data: "test2".data(using: .utf8)!)

        let entry1 = DirectoryEntry(name: "file.txt", type: .file, size: 100, hash: hash1)
        let entry2 = DirectoryEntry(name: "file.txt", type: .file, size: 100, hash: hash1)
        let entry3 = DirectoryEntry(name: "other.txt", type: .file, size: 100, hash: hash2)

        var set: Set<DirectoryEntry> = [entry1, entry2, entry3]
        XCTAssertEqual(set.count, 2) // entry1 and entry2 are equal
    }

    func testDirectoryEntryTypeEquality() {
        XCTAssertEqual(DirectoryEntry.EntryType.file, DirectoryEntry.EntryType.file)
        XCTAssertEqual(DirectoryEntry.EntryType.directory, DirectoryEntry.EntryType.directory)
        XCTAssertNotEqual(DirectoryEntry.EntryType.file, DirectoryEntry.EntryType.directory)
    }

    // MARK: - Hash Collision Resistance

    func testDifferentValuesProduceDifferentHashes() {
        let id1 = CommitID(value: "@1000")
        let id2 = CommitID(value: "@1001")
        let id3 = CommitID(value: "@2000")

        // While hash collisions are theoretically possible, they should be rare
        let hashes: Set<Int> = [id1.hashValue, id2.hashValue, id3.hashValue]
        XCTAssertEqual(hashes.count, 3, "Different CommitIDs should produce different hashes")
    }

    func testSimilarStringsProduceDifferentHashes() {
        let id1 = CommitID(value: "@abc")
        let id2 = CommitID(value: "@abd")
        let id3 = CommitID(value: "@Abc")

        let hashes: Set<Int> = [id1.hashValue, id2.hashValue, id3.hashValue]
        XCTAssertEqual(hashes.count, 3, "Similar strings should produce different hashes")
    }
}
