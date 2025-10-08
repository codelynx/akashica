import Foundation

/// Manages profile configurations in ~/.akashica/configurations/
public actor ProfileManager {
    private let configurationsDir: URL

    public init(configurationsDir: URL? = nil) {
        if let dir = configurationsDir {
            self.configurationsDir = dir
        } else {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            self.configurationsDir = homeDir
                .appendingPathComponent(".akashica")
                .appendingPathComponent("configurations")
        }
    }

    // MARK: - Load Profile

    public func loadProfile(name: String) throws -> ProfileConfig {
        let path = configurationsDir.appendingPathComponent("\(name).json")

        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ProfileError.profileNotFound(name)
        }

        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProfileConfig.self, from: data)
    }

    // MARK: - Save Profile

    public func saveProfile(_ config: ProfileConfig, overwrite: Bool = false) throws {
        let path = configurationsDir.appendingPathComponent("\(config.name).json")

        // Check if profile already exists
        if !overwrite && FileManager.default.fileExists(atPath: path.path) {
            throw ProfileError.profileAlreadyExists(config.name)
        }

        // Create directory if needed
        try FileManager.default.createDirectory(
            at: configurationsDir,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: path)
    }

    // MARK: - Delete Profile

    public func deleteProfile(name: String) throws {
        let path = configurationsDir.appendingPathComponent("\(name).json")

        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ProfileError.profileNotFound(name)
        }

        try FileManager.default.removeItem(at: path)
    }

    // MARK: - List Profiles

    public func listProfiles() throws -> [ProfileConfig] {
        guard FileManager.default.fileExists(atPath: configurationsDir.path) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: configurationsDir,
            includingPropertiesForKeys: nil
        )

        return try contents
            .filter { $0.pathExtension == "json" }
            .map { url in
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(ProfileConfig.self, from: data)
            }
    }

    // MARK: - Profile Exists

    public func profileExists(name: String) -> Bool {
        let path = configurationsDir.appendingPathComponent("\(name).json")
        return FileManager.default.fileExists(atPath: path.path)
    }
}

// MARK: - Errors

public enum ProfileError: Error, CustomStringConvertible {
    case profileNotFound(String)
    case profileAlreadyExists(String)
    case invalidProfileName(String)

    public var description: String {
        switch self {
        case .profileNotFound(let name):
            return "Profile '\(name)' not found. Use 'akashica profile list' to see available profiles."
        case .profileAlreadyExists(let name):
            return "Profile '\(name)' already exists. Use a different name or delete the existing profile first."
        case .invalidProfileName(let name):
            return "Invalid profile name '\(name)'. Profile names must be filesystem-safe (no slashes)."
        }
    }
}
