import XCTest
import TestSupport

final class TestConfigTests: XCTestCase {
    func testAWSConfigLoads() throws {
        guard let config = try AWSTestConfig.load() else {
            throw XCTSkip("AWS credentials not configured - add .credentials/aws-credentials.json to run S3 tests")
        }

        // Validate credentials are populated without printing sensitive data
        XCTAssertFalse(config.accessKeyId.isEmpty, "accessKeyId should not be empty")
        XCTAssertFalse(config.secretAccessKey.isEmpty, "secretAccessKey should not be empty")
        XCTAssertFalse(config.region.isEmpty, "region should not be empty")
        XCTAssertFalse(config.bucket.isEmpty, "bucket should not be empty")
    }
}
