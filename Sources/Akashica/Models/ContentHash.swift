import Foundation

/// Content hash (SHA-256, 64 hex characters)
public struct ContentHash: Hashable, Codable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    /// Create hash from data
    public init(data: Data) {
        self.value = Self.sha256(data: data)
    }

    private static func sha256(data: Data) -> String {
        // TODO: Implement SHA-256 hashing
        // For now, placeholder implementation
        data.base64EncodedString()
    }
}

extension ContentHash: CustomStringConvertible {
    public var description: String {
        value
    }
}

extension ContentHash: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.value = value
    }
}
