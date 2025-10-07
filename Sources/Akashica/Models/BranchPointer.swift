/// Branch pointer to a commit
public struct BranchPointer: Codable, Sendable {
    public let head: CommitID

    public init(head: CommitID) {
        self.head = head
    }
}
