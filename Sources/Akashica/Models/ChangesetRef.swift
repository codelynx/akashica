/// Reference to either a commit or workspace
public enum ChangesetRef: Hashable, Codable, Sendable {
    case commit(CommitID)
    case workspace(WorkspaceID)

    /// Is this changeset read-only?
    public var isReadOnly: Bool {
        switch self {
        case .commit: return true
        case .workspace: return false
        }
    }

    /// Get commit ID (base commit for workspace)
    public var commitID: CommitID {
        switch self {
        case .commit(let id): return id
        case .workspace(let id): return id.baseCommit
        }
    }
}

extension ChangesetRef: CustomStringConvertible {
    public var description: String {
        switch self {
        case .commit(let id): return id.description
        case .workspace(let id): return id.description
        }
    }
}
