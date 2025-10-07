import Foundation
import Akashica

/// Virtual filesystem context (tracks current working directory)
struct VirtualContext {
    let akashicaPath: URL

    /// Read current virtual working directory
    func currentDirectory() -> RepositoryPath {
        let cwdPath = akashicaPath.appendingPathComponent("CWD")

        guard FileManager.default.fileExists(atPath: cwdPath.path),
              let cwdString = try? String(contentsOf: cwdPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            // Default to root
            return RepositoryPath(string: "")
        }

        return RepositoryPath(string: cwdString)
    }

    /// Change virtual working directory
    func changeDirectory(to path: RepositoryPath) throws {
        let cwdPath = akashicaPath.appendingPathComponent("CWD")
        try path.pathString.write(to: cwdPath, atomically: true, encoding: .utf8)
    }

    /// Resolve a path (relative or absolute) based on current directory
    func resolvePath(_ input: String) -> RepositoryPath {
        // Absolute path - normalize from root
        if input.hasPrefix("/") {
            return normalizeAbsolutePath(input)
        }

        // Relative path - start from current directory
        let cwd = currentDirectory()
        var components = cwd.components

        // Split input by '/' and process each segment
        let segments = input.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        for segment in segments {
            if segment == "." {
                // Current directory - skip
                continue
            } else if segment == ".." {
                // Parent directory - pop last component
                if !components.isEmpty {
                    components.removeLast()
                }
                // If already at root, .. has no effect
            } else {
                // Regular component - append
                components.append(segment)
            }
        }

        return RepositoryPath(components: components)
    }

    /// Normalize an absolute path (handles ., .., //)
    private func normalizeAbsolutePath(_ path: String) -> RepositoryPath {
        var components: [String] = []

        // Remove leading / and split
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let segments = cleaned.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        for segment in segments {
            if segment == "." {
                // Current directory - skip
                continue
            } else if segment == ".." {
                // Parent directory - pop last component
                if !components.isEmpty {
                    components.removeLast()
                }
                // If at root, .. has no effect
            } else {
                // Regular component
                components.append(segment)
            }
        }

        return RepositoryPath(components: components)
    }

    /// Initialize virtual context (set CWD to root)
    func initialize() throws {
        try changeDirectory(to: RepositoryPath(string: ""))
    }
}
