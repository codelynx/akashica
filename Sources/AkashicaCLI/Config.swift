import Akashica

/// Reference type (branch or commit)
enum RefType {
    case branch(String)
    case commit(CommitID)

    /// Parse a reference string into branch or commit
    static func parse(_ ref: String) -> RefType {
        if ref.hasPrefix("@") {
            return .commit(CommitID(value: ref))
        } else {
            return .branch(ref)
        }
    }
}
