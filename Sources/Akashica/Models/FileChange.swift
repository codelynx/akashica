/// A file change in a diff
public struct FileChange: Sendable {
    public let path: RepositoryPath
    public let type: ChangeType

    public enum ChangeType: Sendable {
        case added
        case modified
        case deleted
        case renamed(from: RepositoryPath)
    }

    public init(path: RepositoryPath, type: ChangeType) {
        self.path = path
        self.type = type
    }
}
