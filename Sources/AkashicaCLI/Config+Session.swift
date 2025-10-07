import Foundation
import Akashica
import ArgumentParser

extension Config {
    /// Get or create a session for the given URI scope
    /// - Parameter scope: The scope from an AkaURI (currentWorkspace, branch, or commit)
    /// - Returns: A session appropriate for the scope
    /// - Throws: ExitCode.failure if no workspace is active, branch doesn't exist, etc.
    func getSession(for scope: AkaURI.Scope) async throws -> AkashicaSession {
        let repo = try await createValidatedRepository()

        switch scope {
        case .currentWorkspace:
            // Get current workspace ID from config
            guard let workspaceID = try currentWorkspace() else {
                print("Error: No active workspace")
                print("Run 'akashica checkout <branch>' to create a workspace")
                throw ExitCode.failure
            }
            return await repo.session(workspace: workspaceID)

        case .branch(let name):
            // Get session for branch (reads latest commit on branch)
            do {
                return try await repo.session(branch: name)
            } catch {
                print("Error: Branch '\(name)' not found")
                print("Use 'akashica branch' to see available branches")
                throw ExitCode.failure
            }

        case .commit(let commitID):
            // Get session for specific commit
            return await repo.session(commit: commitID)
        }
    }

    /// Resolve URI path to absolute RepositoryPath
    /// - Parameter uri: The parsed AkaURI
    /// - Returns: Absolute RepositoryPath
    /// - Note: Handles relative paths by resolving from virtual CWD
    func resolvePathFromURI(_ uri: AkaURI) throws -> RepositoryPath {
        if uri.isRelativePath {
            // Relative: resolve from virtual CWD
            let vctx = virtualContext()
            return vctx.resolvePath(uri.path)
        } else {
            // Absolute or scoped: use as-is
            return RepositoryPath(string: uri.path)
        }
    }
}
