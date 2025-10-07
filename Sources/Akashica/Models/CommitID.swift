/// Commit identifier (e.g., "@1002")
public struct CommitID: Hashable, Codable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }
}

extension CommitID: CustomStringConvertible {
    public var description: String {
        value
    }
}

extension CommitID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.value = value
    }
}
