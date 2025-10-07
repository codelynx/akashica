import Foundation
import Akashica

/// Akashica URI scheme
///
/// Formats:
/// - aka:/path → Relative path from current virtual CWD
/// - aka:///path → Absolute path from repository root
/// - aka://scope/path → Scoped path (branch or commit)
///
/// Examples:
/// - aka:/tokyo/data.txt → Relative to current CWD
/// - aka:///japan/tokyo/data.txt → Absolute from root
/// - aka://main/config.yml → Branch 'main', /config.yml
/// - aka://@1234/data.csv → Commit @1234, /data.csv
struct AkaURI {
    /// Scope of the URI (what version/context to access)
    enum Scope {
        case currentWorkspace
        case branch(String)
        case commit(CommitID)
    }

    /// The scope (version context)
    let scope: Scope

    /// The path within the repository
    /// For currentWorkspace: can be relative or absolute (based on leading /)
    /// For branch/commit: always absolute (starts with /)
    let path: String

    /// Whether this path is relative (only meaningful for currentWorkspace)
    var isRelativePath: Bool {
        if case .currentWorkspace = scope {
            return !path.hasPrefix("/")
        }
        return false
    }

    /// Check if this is an aka:// URI
    static func isAkaURI(_ string: String) -> Bool {
        return string.hasPrefix("aka://") || string.hasPrefix("aka:/")
    }

    /// Parse an aka:// URI string
    /// - Parameter uriString: The URI to parse
    /// - Throws: AkaURIError if parsing fails
    /// - Returns: Parsed AkaURI
    ///
    /// Formats:
    /// - aka:/path → Relative path, current workspace
    /// - aka:///path → Absolute path, current workspace
    /// - aka://scope/path → Scoped path (branch/commit)
    static func parse(_ uriString: String) throws -> AkaURI {
        // Determine format based on prefix
        if uriString.hasPrefix("aka:///") {
            // Absolute path, current workspace: aka:///path
            let path = String(uriString.dropFirst("aka://".count))
            return AkaURI(scope: .currentWorkspace, path: path)
        } else if uriString.hasPrefix("aka://") {
            // Scoped path: aka://scope/path
            let withoutScheme = String(uriString.dropFirst("aka://".count))

            // Must have scope and path
            guard let firstSlash = withoutScheme.firstIndex(of: "/") else {
                throw AkaURIError.missingPath(uriString)
            }

            let scopeString = String(withoutScheme[..<firstSlash])
            let path = String(withoutScheme[firstSlash...])

            // Parse scope
            let scope = try parseScope(scopeString)
            return AkaURI(scope: scope, path: path)
        } else if uriString.hasPrefix("aka:/") {
            // Relative path, current workspace: aka:/path
            let path = String(uriString.dropFirst("aka:".count))
            return AkaURI(scope: .currentWorkspace, path: path)
        } else {
            throw AkaURIError.invalidScheme(uriString)
        }
    }

    /// Parse the scope (authority) component
    private static func parseScope(_ scopeString: String) throws -> Scope {
        if scopeString.isEmpty {
            return .currentWorkspace
        }

        // Commit: @1234
        if scopeString.hasPrefix("@") {
            let commitID = CommitID(value: scopeString)
            return .commit(commitID)
        }

        // Branch: main, develop, feature/foo
        return .branch(scopeString)
    }

    /// Format the URI back to a string
    func toString() -> String {
        switch scope {
        case .currentWorkspace:
            if path.hasPrefix("/") {
                // Absolute: aka:///path
                return "aka://\(path)"
            } else {
                // Relative: aka:/path
                return "aka:/\(path)"
            }
        case .branch(let name):
            return "aka://\(name)\(path)"
        case .commit(let id):
            return "aka://\(id.value)\(path)"
        }
    }

    /// Check if this scope allows write operations
    var isWritable: Bool {
        switch scope {
        case .currentWorkspace:
            return true
        case .branch, .commit:
            return false  // Read-only
        }
    }

    /// Get a human-readable description of the scope
    var scopeDescription: String {
        switch scope {
        case .currentWorkspace:
            return "current workspace"
        case .branch(let name):
            return "branch '\(name)'"
        case .commit(let id):
            return "commit '\(id.value)'"
        }
    }
}

/// Errors that can occur when parsing an aka:// URI
enum AkaURIError: Error, CustomStringConvertible {
    case invalidScheme(String)
    case missingPath(String)

    var description: String {
        switch self {
        case .invalidScheme(let uri):
            return "Invalid URI scheme: \(uri). Expected 'aka://' or 'aka:/'"
        case .missingPath(let uri):
            return "Missing path in URI: \(uri)"
        }
    }
}
