/// Status of a workspace (what has changed)
public struct WorkspaceStatus: Sendable {
    public let modified: [RepositoryPath]
    public let added: [RepositoryPath]
    public let deleted: [RepositoryPath]
    public let renamed: [(from: RepositoryPath, to: RepositoryPath)]

    public init(
        modified: [RepositoryPath],
        added: [RepositoryPath],
        deleted: [RepositoryPath],
        renamed: [(from: RepositoryPath, to: RepositoryPath)]
    ) {
        self.modified = modified
        self.added = added
        self.deleted = deleted
        self.renamed = renamed
    }
}
