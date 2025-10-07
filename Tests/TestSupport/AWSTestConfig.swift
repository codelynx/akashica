import Foundation

/// AWS test configuration loaded from .credentials/aws-credentials.json
///
/// Shared across all test targets that need AWS credentials.
public struct AWSTestConfig: Codable {
    public let accessKeyId: String
    public let secretAccessKey: String
    public let region: String
    public let bucket: String

    /// Load AWS credentials from project root .credentials directory
    /// Returns nil if credentials file doesn't exist (allows tests to skip gracefully)
    public static func load() throws -> AWSTestConfig? {
        // Find project root using #file macro
        // #file gives: /path/to/akashica/Tests/TestSupport/AWSTestConfig.swift
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // Tests/TestSupport/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // Project root

        let credentialsPath = projectRoot
            .appendingPathComponent(".credentials/aws-credentials.json")

        // Return nil if file doesn't exist (not an error - just skip S3 tests)
        guard FileManager.default.fileExists(atPath: credentialsPath.path) else {
            return nil
        }

        // Load and decode credentials
        let data = try Data(contentsOf: credentialsPath)
        let config = try JSONDecoder().decode(AWSTestConfig.self, from: data)

        return config
    }

    /// Set AWS credentials as environment variables for AWS SDK
    /// Returns the previous values for restoration in tearDown
    public func setEnvironmentVariables() -> [String: String?] {
        let previous = [
            "AWS_ACCESS_KEY_ID": ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"],
            "AWS_SECRET_ACCESS_KEY": ProcessInfo.processInfo.environment["AWS_SECRET_ACCESS_KEY"]
        ]

        setenv("AWS_ACCESS_KEY_ID", accessKeyId, 1)
        setenv("AWS_SECRET_ACCESS_KEY", secretAccessKey, 1)

        return previous
    }

    /// Restore environment variables to their previous state
    public static func restoreEnvironmentVariables(_ previous: [String: String?]) {
        for (key, value) in previous {
            if let value = value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
    }
}
