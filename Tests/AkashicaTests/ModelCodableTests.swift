import XCTest
import Foundation
@testable import Akashica

final class ModelCodableTests: XCTestCase {

    // MARK: - CommitID Tests

    func testCommitIDCodableRoundTrip() throws {
        let original = CommitID(value: "@1002")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CommitID.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.value, "@1002")
    }

    func testCommitIDStringLiteral() {
        let id: CommitID = "@1234"
        XCTAssertEqual(id.value, "@1234")
    }

    func testCommitIDDescription() {
        let id = CommitID(value: "@5678")
        XCTAssertEqual(id.description, "@5678")
    }

    func testCommitIDWithSpecialCharacters() throws {
        let original = CommitID(value: "@commit-v1.2.3")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CommitID.self, from: data)

        XCTAssertEqual(decoded.value, "@commit-v1.2.3")
    }

    // MARK: - WorkspaceID Tests

    func testWorkspaceIDCodableRoundTrip() throws {
        let commitID = CommitID(value: "@1002")
        let original = WorkspaceID(baseCommit: commitID, workspaceSuffix: "a1b3")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorkspaceID.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.baseCommit, commitID)
        XCTAssertEqual(decoded.workspaceSuffix, "a1b3")
    }

    func testWorkspaceIDFullReference() {
        let commitID = CommitID(value: "@1002")
        let workspaceID = WorkspaceID(baseCommit: commitID, workspaceSuffix: "a1b3")

        XCTAssertEqual(workspaceID.fullReference, "@1002$a1b3")
    }

    func testWorkspaceIDDescription() {
        let commitID = CommitID(value: "@1002")
        let workspaceID = WorkspaceID(baseCommit: commitID, workspaceSuffix: "a1b3")

        XCTAssertEqual(workspaceID.description, "@1002$a1b3")
    }

    func testWorkspaceIDNestedEncoding() throws {
        // Verify that nested CommitID is properly encoded
        let original = WorkspaceID(baseCommit: CommitID(value: "@9999"), workspaceSuffix: "xyz1")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)

        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("@9999"))
        XCTAssertTrue(json.contains("xyz1"))

        let decoded = try JSONDecoder().decode(WorkspaceID.self, from: data)
        XCTAssertEqual(decoded.baseCommit.value, "@9999")
        XCTAssertEqual(decoded.workspaceSuffix, "xyz1")
    }

    // MARK: - ChangesetRef Tests

    func testChangesetRefCommitCase() throws {
        let commitID = CommitID(value: "@1002")
        let original = ChangesetRef.commit(commitID)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChangesetRef.self, from: data)

        XCTAssertEqual(decoded, original)

        if case .commit(let decodedCommit) = decoded {
            XCTAssertEqual(decodedCommit, commitID)
        } else {
            XCTFail("Expected .commit case")
        }
    }

    func testChangesetRefWorkspaceCase() throws {
        let workspaceID = WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3")
        let original = ChangesetRef.workspace(workspaceID)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChangesetRef.self, from: data)

        XCTAssertEqual(decoded, original)

        if case .workspace(let decodedWorkspace) = decoded {
            XCTAssertEqual(decodedWorkspace, workspaceID)
        } else {
            XCTFail("Expected .workspace case")
        }
    }

    func testChangesetRefIsReadOnly() {
        let commitRef = ChangesetRef.commit(CommitID(value: "@1002"))
        let workspaceRef = ChangesetRef.workspace(WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3"))

        XCTAssertTrue(commitRef.isReadOnly)
        XCTAssertFalse(workspaceRef.isReadOnly)
    }

    func testChangesetRefCommitID() {
        let commitID = CommitID(value: "@1002")
        let commitRef = ChangesetRef.commit(commitID)

        let workspaceID = WorkspaceID(baseCommit: CommitID(value: "@2000"), workspaceSuffix: "xyz")
        let workspaceRef = ChangesetRef.workspace(workspaceID)

        XCTAssertEqual(commitRef.commitID, commitID)
        XCTAssertEqual(workspaceRef.commitID, CommitID(value: "@2000"))
    }

    func testChangesetRefDescription() {
        let commitRef = ChangesetRef.commit(CommitID(value: "@1002"))
        let workspaceRef = ChangesetRef.workspace(WorkspaceID(baseCommit: CommitID(value: "@1002"), workspaceSuffix: "a1b3"))

        XCTAssertEqual(commitRef.description, "@1002")
        XCTAssertEqual(workspaceRef.description, "@1002$a1b3")
    }

    // MARK: - BranchPointer Tests

    func testBranchPointerCodableRoundTrip() throws {
        let commitID = CommitID(value: "@1002")
        let original = BranchPointer(head: commitID)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BranchPointer.self, from: data)

        XCTAssertEqual(decoded.head, original.head)
    }

    func testBranchPointerJSONFormat() throws {
        let original = BranchPointer(head: CommitID(value: "@5000"))

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)

        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("@5000"))
        XCTAssertTrue(json.contains("head"))
    }

    // MARK: - WorkspaceMetadata Tests

    func testWorkspaceMetadataCodableRoundTrip() throws {
        let commitID = CommitID(value: "@1002")
        let date = Date()
        let original = WorkspaceMetadata(base: commitID, created: date, creator: "alice")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkspaceMetadata.self, from: data)

        XCTAssertEqual(decoded.base, original.base)
        XCTAssertEqual(decoded.created.timeIntervalSince1970, original.created.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertEqual(decoded.creator, "alice")
    }

    func testWorkspaceMetadataDateEncoding() throws {
        let commitID = CommitID(value: "@1002")
        let date = Date(timeIntervalSince1970: 1609459200) // 2021-01-01 00:00:00 UTC
        let original = WorkspaceMetadata(base: commitID, created: date, creator: "test-user")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(original)

        let json = String(data: data, encoding: .utf8)!
        // Verify ISO8601 format is used
        XCTAssertTrue(json.contains("2021"))
        XCTAssertTrue(json.contains("T"))
        XCTAssertTrue(json.contains("Z"))
    }

    func testWorkspaceMetadataAllFields() throws {
        let commitID = CommitID(value: "@9999")
        let date = Date()
        let original = WorkspaceMetadata(base: commitID, created: date, creator: "bob")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkspaceMetadata.self, from: data)

        XCTAssertEqual(decoded.base.value, "@9999")
        XCTAssertEqual(decoded.creator, "bob")
        XCTAssertNotNil(decoded.created)
    }

    // MARK: - Edge Cases

    func testEmptyStringValues() throws {
        let commitID = CommitID(value: "")
        let data = try JSONEncoder().encode(commitID)
        let decoded = try JSONDecoder().decode(CommitID.self, from: data)

        XCTAssertEqual(decoded.value, "")
    }

    func testLongStringValues() throws {
        let longValue = String(repeating: "a", count: 10000)
        let commitID = CommitID(value: longValue)

        let data = try JSONEncoder().encode(commitID)
        let decoded = try JSONDecoder().decode(CommitID.self, from: data)

        XCTAssertEqual(decoded.value, longValue)
    }

    func testUnicodeInValues() throws {
        let commitID = CommitID(value: "@コミット-123-日本語")

        let data = try JSONEncoder().encode(commitID)
        let decoded = try JSONDecoder().decode(CommitID.self, from: data)

        XCTAssertEqual(decoded.value, "@コミット-123-日本語")
    }

    func testWorkspaceMetadataWithSpecialCreatorName() throws {
        let original = WorkspaceMetadata(
            base: CommitID(value: "@1000"),
            created: Date(),
            creator: "user@example.com <User Name>"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WorkspaceMetadata.self, from: data)

        XCTAssertEqual(decoded.creator, "user@example.com <User Name>")
    }
}
