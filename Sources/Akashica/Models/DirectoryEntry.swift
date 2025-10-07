/// Entry in a directory listing
public struct DirectoryEntry: Hashable, Sendable {
    public let name: String
    public let type: EntryType
    public let size: Int64
    public let hash: ContentHash

    public enum EntryType: Hashable, Sendable {
        case file
        case directory
    }

    public init(name: String, type: EntryType, size: Int64, hash: ContentHash) {
        self.name = name
        self.type = type
        self.size = size
        self.hash = hash
    }
}
