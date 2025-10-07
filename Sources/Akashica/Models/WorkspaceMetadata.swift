import Foundation

/// Metadata for a workspace
public struct WorkspaceMetadata: Codable, Sendable {
    public let base: CommitID
    public let created: Date
    public let creator: String

    public init(base: CommitID, created: Date, creator: String) {
        self.base = base
        self.created = created
        self.creator = creator
    }
}
