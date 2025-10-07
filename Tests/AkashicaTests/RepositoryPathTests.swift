import XCTest
@testable import Akashica

final class RepositoryPathTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitFromEmptyString() {
        let path = RepositoryPath(string: "")
        XCTAssertTrue(path.components.isEmpty)
        XCTAssertTrue(path.isRoot)
    }

    func testInitFromSingleComponent() {
        let path = RepositoryPath(string: "file.txt")
        XCTAssertEqual(path.components, ["file.txt"])
        XCTAssertEqual(path.name, "file.txt")
        XCTAssertFalse(path.isRoot)
    }

    func testInitFromNestedPath() {
        let path = RepositoryPath(string: "asia/japan/tokyo.txt")
        XCTAssertEqual(path.components, ["asia", "japan", "tokyo.txt"])
        XCTAssertEqual(path.name, "tokyo.txt")
        XCTAssertFalse(path.isRoot)
    }

    func testInitFromComponents() {
        let path = RepositoryPath(components: ["asia", "japan", "tokyo.txt"])
        XCTAssertEqual(path.components, ["asia", "japan", "tokyo.txt"])
        XCTAssertEqual(path.pathString, "asia/japan/tokyo.txt")
    }

    func testInitFromEmptyComponents() {
        let path = RepositoryPath(components: [])
        XCTAssertTrue(path.components.isEmpty)
        XCTAssertTrue(path.isRoot)
        XCTAssertEqual(path.pathString, "")
    }

    // MARK: - Edge Cases

    func testTrailingSlash() {
        let path = RepositoryPath(string: "asia/japan/")
        // Trailing slash creates empty component which gets filtered by split
        XCTAssertEqual(path.components, ["asia", "japan"])
    }

    func testLeadingSlash() {
        let path = RepositoryPath(string: "/asia/japan")
        // Leading slash creates empty component which gets filtered by split
        XCTAssertEqual(path.components, ["asia", "japan"])
    }

    func testMultipleSlashes() {
        let path = RepositoryPath(string: "asia//japan")
        // Double slash creates empty component which gets filtered by split
        XCTAssertEqual(path.components, ["asia", "japan"])
    }

    func testSingleSlash() {
        let path = RepositoryPath(string: "/")
        // Single slash results in root path
        XCTAssertTrue(path.components.isEmpty)
        XCTAssertTrue(path.isRoot)
    }

    func testPathWithSpaces() {
        let path = RepositoryPath(string: "my folder/my file.txt")
        XCTAssertEqual(path.components, ["my folder", "my file.txt"])
        XCTAssertEqual(path.name, "my file.txt")
    }

    func testPathWithUnicode() {
        let path = RepositoryPath(string: "日本/東京.txt")
        XCTAssertEqual(path.components, ["日本", "東京.txt"])
        XCTAssertEqual(path.name, "東京.txt")
    }

    func testPathWithDots() {
        let path = RepositoryPath(string: "folder/file.tar.gz")
        XCTAssertEqual(path.components, ["folder", "file.tar.gz"])
        XCTAssertEqual(path.name, "file.tar.gz")
    }

    // MARK: - Parent Tests

    func testParentOfRootPath() {
        let path = RepositoryPath(string: "")
        XCTAssertNil(path.parent)
    }

    func testParentOfSingleComponent() {
        let path = RepositoryPath(string: "file.txt")
        let parent = path.parent
        XCTAssertNotNil(parent)
        XCTAssertTrue(parent!.isRoot)
        XCTAssertTrue(parent!.components.isEmpty)
    }

    func testParentOfNestedPath() {
        let path = RepositoryPath(string: "asia/japan/tokyo.txt")
        let parent = path.parent
        XCTAssertNotNil(parent)
        XCTAssertEqual(parent!.components, ["asia", "japan"])
        XCTAssertEqual(parent!.pathString, "asia/japan")
    }

    func testParentChain() {
        let path = RepositoryPath(string: "a/b/c/d.txt")

        let parent1 = path.parent
        XCTAssertEqual(parent1?.pathString, "a/b/c")

        let parent2 = parent1?.parent
        XCTAssertEqual(parent2?.pathString, "a/b")

        let parent3 = parent2?.parent
        XCTAssertEqual(parent3?.pathString, "a")

        let parent4 = parent3?.parent
        XCTAssertTrue(parent4?.isRoot ?? false)

        let parent5 = parent4?.parent
        XCTAssertNil(parent5)
    }

    // MARK: - Name Tests

    func testNameOfRootPath() {
        let path = RepositoryPath(string: "")
        XCTAssertNil(path.name)
    }

    func testNameOfSingleComponent() {
        let path = RepositoryPath(string: "file.txt")
        XCTAssertEqual(path.name, "file.txt")
    }

    func testNameOfNestedPath() {
        let path = RepositoryPath(string: "asia/japan/tokyo.txt")
        XCTAssertEqual(path.name, "tokyo.txt")
    }

    // MARK: - isRoot Tests

    func testIsRootForEmptyPath() {
        let path = RepositoryPath(string: "")
        XCTAssertTrue(path.isRoot)
    }

    func testIsRootForNonEmptyPath() {
        let path = RepositoryPath(string: "asia")
        XCTAssertFalse(path.isRoot)
    }

    // MARK: - pathString Tests

    func testPathStringForRoot() {
        let path = RepositoryPath(components: [])
        XCTAssertEqual(path.pathString, "")
    }

    func testPathStringForSingleComponent() {
        let path = RepositoryPath(components: ["file.txt"])
        XCTAssertEqual(path.pathString, "file.txt")
    }

    func testPathStringForNestedPath() {
        let path = RepositoryPath(components: ["asia", "japan", "tokyo.txt"])
        XCTAssertEqual(path.pathString, "asia/japan/tokyo.txt")
    }

    func testPathStringRoundTrip() {
        let original = "asia/japan/tokyo.txt"
        let path = RepositoryPath(string: original)
        XCTAssertEqual(path.pathString, original)
    }

    // MARK: - CustomStringConvertible Tests

    func testDescription() {
        let path = RepositoryPath(string: "asia/japan/tokyo.txt")
        XCTAssertEqual(path.description, "asia/japan/tokyo.txt")
    }

    func testDescriptionForRoot() {
        let path = RepositoryPath(string: "")
        XCTAssertEqual(path.description, "")
    }

    // MARK: - ExpressibleByStringLiteral Tests

    func testStringLiteralInitialization() {
        let path: RepositoryPath = "asia/japan/tokyo.txt"
        XCTAssertEqual(path.components, ["asia", "japan", "tokyo.txt"])
    }

    func testStringLiteralEmpty() {
        let path: RepositoryPath = ""
        XCTAssertTrue(path.isRoot)
    }

    // MARK: - Hashable Tests

    func testEqualityForSamePaths() {
        let path1 = RepositoryPath(string: "asia/japan/tokyo.txt")
        let path2 = RepositoryPath(string: "asia/japan/tokyo.txt")
        XCTAssertEqual(path1, path2)
    }

    func testEqualityForDifferentPaths() {
        let path1 = RepositoryPath(string: "asia/japan/tokyo.txt")
        let path2 = RepositoryPath(string: "asia/japan/kyoto.txt")
        XCTAssertNotEqual(path1, path2)
    }

    func testEqualityForRootPaths() {
        let path1 = RepositoryPath(string: "")
        let path2 = RepositoryPath(components: [])
        XCTAssertEqual(path1, path2)
    }

    func testHashConsistency() {
        let path1 = RepositoryPath(string: "asia/japan/tokyo.txt")
        let path2 = RepositoryPath(string: "asia/japan/tokyo.txt")
        XCTAssertEqual(path1.hashValue, path2.hashValue)
    }

    func testSetUsage() {
        let path1 = RepositoryPath(string: "asia/japan/tokyo.txt")
        let path2 = RepositoryPath(string: "asia/japan/tokyo.txt")
        let path3 = RepositoryPath(string: "asia/japan/kyoto.txt")

        var set: Set<RepositoryPath> = [path1, path2, path3]
        XCTAssertEqual(set.count, 2) // path1 and path2 are equal
        XCTAssertTrue(set.contains(path1))
        XCTAssertTrue(set.contains(path3))
    }

    func testDictionaryUsage() {
        let path1 = RepositoryPath(string: "asia/japan/tokyo.txt")
        let path2 = RepositoryPath(string: "asia/japan/kyoto.txt")

        var dict: [RepositoryPath: String] = [:]
        dict[path1] = "Tokyo"
        dict[path2] = "Kyoto"

        XCTAssertEqual(dict[path1], "Tokyo")
        XCTAssertEqual(dict[path2], "Kyoto")
        XCTAssertEqual(dict.count, 2)
    }

    // MARK: - Codable Tests

    func testCodableRoundTrip() throws {
        let original = RepositoryPath(string: "asia/japan/tokyo.txt")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RepositoryPath.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.components, original.components)
    }

    func testCodableRootPath() throws {
        let original = RepositoryPath(string: "")

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RepositoryPath.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.isRoot)
    }

    func testCodablePreservesComponents() throws {
        let original = RepositoryPath(components: ["asia", "japan", "tokyo.txt"])

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RepositoryPath.self, from: data)

        XCTAssertEqual(decoded.components, ["asia", "japan", "tokyo.txt"])
    }
}
