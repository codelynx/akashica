import Foundation
import CryptoKit

/// Content hash (SHA-256, 64 hex characters)
public struct ContentHash: Hashable, Codable, Sendable {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    /// Create hash from data using SHA-256
    public init(data: Data) {
        self.value = Self.sha256(data: data)
    }

    private static func sha256(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
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
