import Foundation

/// Entry in a directory manifest
public struct ManifestEntry {
    public let hash: String
    public let size: Int64
    public let name: String
    public let isDirectory: Bool

    public init(hash: String, size: Int64, name: String, isDirectory: Bool) {
        self.hash = hash
        self.size = size
        self.name = name
        self.isDirectory = isDirectory
    }
}

/// Parses directory manifests in format: `{hash}:{size}:{name}`
public struct ManifestParser {
    public init() {}

    /// Parse manifest data into entries
    /// Format: newline-delimited `{hash}:{size}:{name}`
    /// Directories end with `/` in the name
    public func parse(_ data: Data) throws -> [ManifestEntry] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw ManifestError.invalidEncoding
        }

        return try content
            .split(separator: "\n")
            .filter { !$0.isEmpty }
            .map { line in
                try parseLine(String(line))
            }
    }

    private func parseLine(_ line: String) throws -> ManifestEntry {
        let parts = line.split(separator: ":", maxSplits: 2)
        guard parts.count == 3 else {
            throw ManifestError.invalidFormat(line)
        }

        let hash = String(parts[0])
        guard let size = Int64(parts[1]) else {
            throw ManifestError.invalidSize(String(parts[1]))
        }
        let name = String(parts[2])

        let isDirectory = name.hasSuffix("/")
        let cleanName = isDirectory ? String(name.dropLast()) : name

        return ManifestEntry(
            hash: hash,
            size: size,
            name: cleanName,
            isDirectory: isDirectory
        )
    }
}

/// Builds directory manifests
public struct ManifestBuilder {
    public init() {}

    /// Build manifest data from entries
    /// Format: newline-delimited `{hash}:{size}:{name}`
    /// Directories will have `/` appended to name
    public func build(entries: [ManifestEntry]) -> Data {
        let lines = entries.map { entry in
            let name = entry.isDirectory ? "\(entry.name)/" : entry.name
            return "\(entry.hash):\(entry.size):\(name)"
        }
        let content = lines.joined(separator: "\n")
        return content.data(using: .utf8) ?? Data()
    }
}

public enum ManifestError: Error {
    case invalidEncoding
    case invalidFormat(String)
    case invalidSize(String)
}
