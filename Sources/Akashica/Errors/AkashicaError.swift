import Foundation

/// Errors that can occur in Akashica operations
public enum AkashicaError: Error {
    case sessionReadOnly
    case workspaceNotFound(WorkspaceID)
    case commitNotFound(CommitID)
    case fileNotFound(RepositoryPath)
    case branchNotFound(String)
    case branchConflict(branch: String, expected: CommitID, actual: CommitID?)
    case invalidManifest(String)
    case storageError(Error)
}

extension AkashicaError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sessionReadOnly:
            return "Session is read-only. Cannot modify files in a commit session."
        case .workspaceNotFound(let id):
            return "Workspace not found: \(id)"
        case .commitNotFound(let id):
            return "Commit not found: \(id)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .branchNotFound(let name):
            return "Branch not found: \(name)"
        case .branchConflict(let branch, let expected, let actual):
            if let actual = actual {
                return "Branch conflict: \(branch) expected \(expected) but was \(actual)"
            } else {
                return "Branch conflict: \(branch) expected \(expected) but branch does not exist"
            }
        case .invalidManifest(let reason):
            return "Invalid manifest: \(reason)"
        case .storageError(let error):
            return "Storage error: \(error.localizedDescription)"
        }
    }
}
