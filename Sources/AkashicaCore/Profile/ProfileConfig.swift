import Foundation

/// Profile configuration stored in ~/.akashica/configurations/{name}.json
public struct ProfileConfig: Codable {
    public let version: String
    public let name: String
    public let storage: StorageConfig
    public let created: Date

    public init(
        version: String = "1.0",
        name: String,
        storage: StorageConfig,
        created: Date = Date()
    ) {
        self.version = version
        self.name = name
        self.storage = storage
        self.created = created
    }

    public struct StorageConfig: Codable {
        public let type: String  // "local" or "s3"
        public let path: String? // For local storage
        public let bucket: String?  // For S3
        public let prefix: String?  // For S3
        public let region: String?  // For S3

        public init(
            type: String,
            path: String? = nil,
            bucket: String? = nil,
            prefix: String? = nil,
            region: String? = nil
        ) {
            self.type = type
            self.path = path
            self.bucket = bucket
            self.prefix = prefix
            self.region = region
        }

        public static func local(path: String) -> StorageConfig {
            StorageConfig(type: "local", path: path)
        }

        public static func s3(
            bucket: String,
            prefix: String? = nil,
            region: String = "us-east-1"
        ) -> StorageConfig {
            StorageConfig(
                type: "s3",
                bucket: bucket,
                prefix: prefix,
                region: region
            )
        }
    }
}
