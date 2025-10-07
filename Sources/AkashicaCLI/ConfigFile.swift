import Foundation

/// Configuration file format (.akashica/config.json)
struct ConfigFile: Codable {
    var repository: RepositoryConfig?
    var storage: StorageConfig?
    var cache: CacheConfig?
    var ui: UIConfig?

    struct RepositoryConfig: Codable {
        var name: String?
        var version: String?
    }

    struct StorageConfig: Codable {
        var type: String? // "local" or "s3"
        var bucket: String?
        var region: String?
        var prefix: String?
        var credentials: CredentialsConfig?

        struct CredentialsConfig: Codable {
            var mode: String? // "chain" or "static"
            var accessKeyId: String?
            var secretAccessKey: String?

            enum CodingKeys: String, CodingKey {
                case mode
                case accessKeyId = "access_key_id"
                case secretAccessKey = "secret_access_key"
            }
        }
    }

    struct CacheConfig: Codable {
        var enabled: Bool?
        var localPath: String?
        var maxSize: String?

        enum CodingKeys: String, CodingKey {
            case enabled
            case localPath = "local_path"
            case maxSize = "max_size"
        }
    }

    struct UIConfig: Codable {
        var color: Bool?
        var progress: Bool?
    }
}

extension ConfigFile {
    /// Read config file from .akashica/config.json
    static func read(from akashicaPath: URL) throws -> ConfigFile? {
        let configPath = akashicaPath.appendingPathComponent("config.json")

        guard FileManager.default.fileExists(atPath: configPath.path) else {
            return nil
        }

        let data = try Data(contentsOf: configPath)
        let decoder = JSONDecoder()
        return try decoder.decode(ConfigFile.self, from: data)
    }

    /// Write config file to .akashica/config.json
    func write(to akashicaPath: URL) throws {
        let configPath = akashicaPath.appendingPathComponent("config.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: configPath, options: .atomic)
    }
}
