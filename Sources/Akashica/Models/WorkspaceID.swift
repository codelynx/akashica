/// Workspace identifier (e.g., "@1002$a1b3")
public struct WorkspaceID: Hashable, Codable, Sendable {
    public let baseCommit: CommitID
    public let workspaceSuffix: String

    public init(baseCommit: CommitID, workspaceSuffix: String) {
        self.baseCommit = baseCommit
        self.workspaceSuffix = workspaceSuffix
    }

    /// Full workspace reference (e.g., "@1002$a1b3")
    public var fullReference: String {
        "\(baseCommit.value)$\(workspaceSuffix)"
    }
}

extension WorkspaceID: CustomStringConvertible {
    public var description: String {
        fullReference
    }
}
