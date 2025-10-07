import ArgumentParser
import Foundation
import Akashica

struct Cp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Copy files between local filesystem and repository",
        discussion: """
        Use aka:// URIs to reference repository content:

        Examples:
          akashica cp ~/photo.jpg aka:///vacation/photo.jpg      # Upload (absolute)
          akashica cp ~/doc.pdf aka:/reports/doc.pdf             # Upload (relative)
          akashica cp aka:///reports/q3.pdf ~/Desktop/           # Download (absolute)
          akashica cp aka:/data.txt /tmp/data.txt                # Download (relative)
          akashica cp aka://main/config.yml /tmp/config.yml      # Download from branch

        Path types:
          aka:///path      - Absolute repository path
          aka:/path        - Relative to virtual CWD
          aka://main/path  - From branch 'main'
          aka://@1234/path - From commit @1234
          ~/path, ./path   - Local filesystem

        Note: All repository paths must use aka:// scheme.
        """
    )

    @OptionGroup var storage: StorageOptions

    @Argument(help: "Source path (local or aka:// URI)")
    var source: String

    @Argument(help: "Destination path (local or aka:// URI)")
    var destination: String

    func run() async throws {
        let config = storage.makeConfig()

        // Determine if paths are local or remote
        let srcIsRemote = AkaURI.isAkaURI(source)
        let dstIsRemote = AkaURI.isAkaURI(destination)

        switch (srcIsRemote, dstIsRemote) {
        case (true, true):
            // Remote → Remote (not yet supported)
            print("Error: Remote-to-remote copy not yet supported")
            throw ExitCode.failure

        case (false, true):
            // Local → Remote (upload)
            try await uploadFile(config: config)

        case (true, false):
            // Remote → Local (download)
            try await downloadFile(config: config)

        case (false, false):
            // Local → Local
            print("Error: Both paths are local")
            print("Use standard 'cp' command for local-to-local copies")
            throw ExitCode.failure
        }
    }

    /// Upload file from local filesystem to repository
    private func uploadFile(config: Config) async throws {
        // Parse destination URI
        let uri = try AkaURI.parse(destination)

        // Validate writable
        guard uri.isWritable else {
            print("Error: Cannot write to read-only scope: \(uri.scopeDescription)")
            print("Only current workspace (aka:/// or aka:/) supports writes")
            throw ExitCode.failure
        }

        // Get session and resolve path
        let session = try await config.getSession(for: uri.scope)
        let remotePath = try config.resolvePathFromURI(uri)

        // Expand local path
        let expandedPath = (source as NSString).expandingTildeInPath
        let localURL = URL(fileURLWithPath: expandedPath)

        // Check if local file exists and is not a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDirectory) else {
            print("Error: Local file not found: \(source)")
            throw ExitCode.failure
        }

        if isDirectory.boolValue {
            print("Error: Directory uploads not supported")
            print("Upload individual files instead")
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

        // Upload to session
        do {
            try await session.writeFile(data, to: remotePath)
            print("Uploaded \(source) → \(remotePath.pathString) (\(formatSize(Int64(data.count))))")
        } catch {
            print("Error: Failed to upload file: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    /// Download file from repository to local filesystem
    private func downloadFile(config: Config) async throws {
        // Parse source URI
        let uri = try AkaURI.parse(source)

        // Get session and resolve path
        let session = try await config.getSession(for: uri.scope)
        let remotePath = try config.resolvePathFromURI(uri)

        // Read from session
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

        // Expand local path
        let expandedPath = (destination as NSString).expandingTildeInPath
        var localURL = URL(fileURLWithPath: expandedPath)

        // If destination is a directory, append remote filename
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            if let filename = remotePath.name {
                localURL = localURL.appendingPathComponent(filename)
            }
        }

        // Write to local file
        do {
            try data.write(to: localURL, options: .atomic)
            print("Downloaded \(remotePath.pathString) → \(localURL.path) (\(formatSize(Int64(data.count))))")
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
