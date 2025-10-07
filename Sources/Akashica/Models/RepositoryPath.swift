/// Repository path (e.g., "asia/japan/tokyo.txt")
public struct RepositoryPath: Hashable, Codable, Sendable {
    public let components: [String]

    public init(components: [String]) {
        self.components = components
    }

    /// Create from path string (e.g., "asia/japan/tokyo.txt")
    public init(string: String) {
        self.components = string.split(separator: "/").map(String.init)
    }

    /// Full path as string
    public var pathString: String {
        components.joined(separator: "/")
    }

    /// Parent path (nil if root)
    public var parent: RepositoryPath? {
        guard !components.isEmpty else { return nil }
        return RepositoryPath(components: Array(components.dropLast()))
    }

    /// File/directory name
    public var name: String? {
        components.last
    }

    /// Is root path
    public var isRoot: Bool {
        components.isEmpty
    }
}

extension RepositoryPath: CustomStringConvertible {
    public var description: String {
        pathString
    }
}

extension RepositoryPath: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(string: value)
    }
}
