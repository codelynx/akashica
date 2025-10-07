import XCTest
@testable import Akashica

final class ContentHashTests: XCTestCase {
    func testSHA256HashFormat() {
        // Test with known input
        let testData = "Hello, World!".data(using: .utf8)!
        let hash = ContentHash(data: testData)

        // Verify length (SHA-256 = 64 hex characters)
        XCTAssertEqual(hash.value.count, 64, "SHA-256 hash should be 64 characters")

        // Verify expected hash value
        XCTAssertEqual(
            hash.value,
            "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f",
            "Hash should match known SHA-256 output"
        )

        // Verify all characters are hex
        let hexCharset = CharacterSet(charactersIn: "0123456789abcdef")
        let hashCharset = CharacterSet(charactersIn: hash.value)
        XCTAssertTrue(hexCharset.isSuperset(of: hashCharset), "Hash should only contain hex characters")
    }

    func testEmptyData() {
        let emptyData = Data()
        let hash = ContentHash(data: emptyData)

        // SHA-256 of empty string
        XCTAssertEqual(
            hash.value,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            "Hash of empty data should match known value"
        )
    }

    func testDifferentInputsProduceDifferentHashes() {
        let data1 = "test1".data(using: .utf8)!
        let data2 = "test2".data(using: .utf8)!

        let hash1 = ContentHash(data: data1)
        let hash2 = ContentHash(data: data2)

        XCTAssertNotEqual(hash1.value, hash2.value, "Different inputs should produce different hashes")
    }

    func testSameInputProducesSameHash() {
        let data = "consistent".data(using: .utf8)!

        let hash1 = ContentHash(data: data)
        let hash2 = ContentHash(data: data)

        XCTAssertEqual(hash1.value, hash2.value, "Same input should always produce same hash")
    }
}
