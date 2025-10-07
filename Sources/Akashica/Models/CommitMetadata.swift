import Foundation

/// Metadata for a commit
public struct CommitMetadata: Codable, Sendable {
    /// Commit message describing the changes
    public let message: String

    /// Author of the commit
    public let author: String

    /// Timestamp when the commit was created
    public let timestamp: Date

    /// Parent commit (nil for initial commit)
    public let parent: CommitID?

    public init(
        message: String,
        author: String,
        timestamp: Date,
        parent: CommitID?
    ) {
        self.message = message
        self.author = author
        self.timestamp = timestamp
        self.parent = parent
    }
}

extension CommitMetadata: Hashable {}
