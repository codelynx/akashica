import Foundation

/// Tombstone marker for intentionally deleted content
///
/// When sensitive content is scrubbed from the repository, the actual
/// object data is deleted but a tombstone marker is left in its place.
/// This distinguishes intentional deletion (compliance, security) from
/// storage corruption or missing data.
///
/// Storage location:
/// - Local: `objects/<hash>.tomb`
/// - S3: `objects/<hash>.tomb`
public struct Tombstone: Codable, Sendable, Hashable {
    /// Hash of the deleted content
    public let deletedHash: ContentHash

    /// Explanation of why content was deleted (required for audit trail)
    public let reason: String

    /// When the content was deleted
    public let timestamp: Date

    /// Who authorized the deletion (email, username, or identifier)
    public let deletedBy: String

    /// Original size of the deleted content in bytes (if known)
    public let originalSize: Int64?

    public init(
        deletedHash: ContentHash,
        reason: String,
        timestamp: Date = Date(),
        deletedBy: String,
        originalSize: Int64? = nil
    ) {
        self.deletedHash = deletedHash
        self.reason = reason
        self.timestamp = timestamp
        self.deletedBy = deletedBy
        self.originalSize = originalSize
    }
}
