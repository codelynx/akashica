import ArgumentParser
import Foundation
import Akashica

struct Cp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Copy files between local filesystem and virtual filesystem",
        discussion: """
        Path detection rules:
        - Remote (virtual FS): bare names (banana.txt), paths with slashes (foo/bar.txt), absolute repo paths (/japan/file.txt)
        - Local (filesystem): ~/, ./, ../ prefixes
        - Explicit: local:/path or remote:/path to override

        Examples:
          akashica cp ./foo.pdf banana.txt        # Upload to virtual FS
          akashica cp banana.txt ./out.pdf        # Download from virtual FS
          akashica cp ~/file.txt /docs/file.txt   # Upload to /docs/file.txt (remote)
          akashica cp report.pdf local:/tmp/out.pdf  # Download to /tmp (use local: prefix!)

        Note: Absolute paths like /tmp/file are treated as remote by default.
        Use local:/tmp/file to explicitly specify local filesystem.
        """
    )

    @OptionGroup var storage: StorageOptions

    @Argument(help: "Source path")
    var source: String

    @Argument(help: "Destination path")
    var destination: String

    func run() async throws {
        let config = storage.makeConfig()

        // Determine direction based on path format
        let isSourceLocal = isLocalPath(source)
        let isDestLocal = isLocalPath(destination)

        if isSourceLocal && isDestLocal {
            print("Error: Both source and destination are local paths")
            print("Use standard 'cp' command for local-to-local copies")
            throw ExitCode.failure
        }

        if !isSourceLocal && !isDestLocal {
            print("Error: Remote-to-remote copy not yet supported")
            print("Download first with: akashica cp \(source) /tmp/file")
            print("Then upload with: akashica cp /tmp/file \(destination)")
            throw ExitCode.failure
        }

        // Get current workspace
        guard let workspace = try config.currentWorkspace() else {
            print("Error: Not in a workspace. Use 'akashica checkout' to create one.")
            throw ExitCode.failure
        }

        // Create session
        let repo = try await config.createValidatedRepository()
        let session = await repo.session(workspace: workspace)
        let vctx = config.virtualContext()

        if isSourceLocal {
            // Local → Remote (upload)
            let remoteDest = stripPrefix(destination)
            try await uploadFile(
                localPath: source,
                remotePath: vctx.resolvePath(remoteDest),
                session: session
            )
        } else {
            // Remote → Local (download)
            let remoteSrc = stripPrefix(source)
            try await downloadFile(
                remotePath: vctx.resolvePath(remoteSrc),
                localPath: destination,
                session: session
            )
        }
    }

    /// Check if path is local filesystem path
    /// Local paths:
    ///   - Start with ~, ./, ../
    ///   - Absolute filesystem paths (but NOT repository paths starting with /)
    ///   - Use explicit local: prefix
    /// Remote paths:
    ///   - Everything else (including bare names like "banana.txt")
    ///   - Absolute repository paths like /japan/tokyo/file.txt
    ///   - Use explicit remote: prefix
    private func isLocalPath(_ path: String) -> Bool {
        // Explicit prefix
        if path.hasPrefix("local:") {
            return true
        }
        if path.hasPrefix("remote:") {
            return false
        }

        // Local indicators
        if path.hasPrefix("~/") || path == "~" {
            return true  // Home directory
        }
        if path.hasPrefix("./") || path.hasPrefix("../") {
            return true  // Relative to current local directory
        }

        // Absolute paths starting with / are tricky:
        // We treat them as REMOTE (repository paths) by default
        // This allows: cp /local/file.txt /remote/path  to work as local→remote
        // If user wants local absolute path, they use: cp local:/usr/file.txt ...

        // Everything else (bare names, paths with slashes) = REMOTE
        return false
    }

    /// Strip prefix from path (local: or remote:)
    private func stripPrefix(_ path: String) -> String {
        if path.hasPrefix("local:") {
            return String(path.dropFirst("local:".count))
        }
        if path.hasPrefix("remote:") {
            return String(path.dropFirst("remote:".count))
        }
        return path
    }

    /// Upload file from local filesystem to workspace
    private func uploadFile(
        localPath: String,
        remotePath: RepositoryPath,
        session: AkashicaSession
    ) async throws {
        // Strip prefix and expand ~ in local path
        let cleanPath = stripPrefix(localPath)
        let expandedPath = (cleanPath as NSString).expandingTildeInPath
        let localURL = URL(fileURLWithPath: expandedPath)

        // Check if local file exists
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            print("Error: Local file not found: \(localPath)")
            throw ExitCode.failure
        }

        // Read local file
        let data: Data
        do {
            data = try Data(contentsOf: localURL)
        } catch {
            print("Error: Cannot read local file: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        // Upload to workspace
        do {
            try await session.writeFile(data, to: remotePath)
            print("Uploaded \(localPath) → \(remotePath.pathString) (\(formatSize(Int64(data.count))))")
        } catch {
            print("Error: Failed to upload file: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    /// Download file from workspace to local filesystem
    private func downloadFile(
        remotePath: RepositoryPath,
        localPath: String,
        session: AkashicaSession
    ) async throws {
        // Read from workspace
        let data: Data
        do {
            data = try await session.readFile(at: remotePath)
        } catch AkashicaError.fileNotFound {
            print("Error: Remote file not found: \(remotePath.pathString)")
            throw ExitCode.failure
        } catch {
            print("Error: Failed to read remote file: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        // Strip prefix and expand ~ in local path
        let cleanPath = stripPrefix(localPath)
        let expandedPath = (cleanPath as NSString).expandingTildeInPath
        let localURL = URL(fileURLWithPath: expandedPath)

        // Write to local file
        do {
            try data.write(to: localURL, options: .atomic)
            print("Downloaded \(remotePath.pathString) → \(localPath) (\(formatSize(Int64(data.count))))")
        } catch {
            print("Error: Cannot write local file: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes)B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1fK", Double(bytes) / 1024.0)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1fM", Double(bytes) / (1024.0 * 1024.0))
        } else {
            return String(format: "%.1fG", Double(bytes) / (1024.0 * 1024.0 * 1024.0))
        }
    }
}
