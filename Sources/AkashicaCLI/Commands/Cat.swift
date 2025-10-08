import ArgumentParser
import Foundation
import Akashica

struct Cat: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Display file contents from repository",
        discussion: """
        Use aka:// URIs to reference repository content:

        Examples:
          akashica cat aka:///reports/q3.pdf              # Absolute path
          akashica cat aka:/data.txt                      # Relative to virtual CWD
          akashica cat aka://main/config.yml              # From branch 'main'
          akashica cat aka://@1234/data/historical.csv    # From commit @1234

        Path types:
          aka:///path      - Absolute repository path
          aka:/path        - Relative to virtual CWD
          aka://main/path  - From branch 'main'
          aka://@1234/path - From commit @1234
        """
    )

    @Option(name: .long, help: "Profile name (defaults to AKASHICA_PROFILE environment variable)")
    var profile: String?

    @Argument(help: "File path (aka:// URI)")
    var path: String

    func run() async throws {
        let context = try await CommandContext.resolve(profileFlag: profile)

        // Parse URI
        let uri = try AkaURI.parse(path)

        // Get session and resolve path
        let session = try await context.getSession(for: uri.scope)
        let targetPath = context.resolvePathFromURI(uri)

        // Read file
        do {
            let data = try await session.readFile(at: targetPath)

            // Write to stdout
            if let text = String(data: data, encoding: .utf8) {
                print(text, terminator: "")
            } else {
                // Binary file - write raw data to stdout
                FileHandle.standardOutput.write(data)
            }
        } catch AkashicaError.fileNotFound {
            print("Error: File not found: \(targetPath.pathString)", to: &standardError)
            throw ExitCode.failure
        }
    }
}

// Helper to print to stderr
private var standardError = FileHandleOutputStream(fileHandle: FileHandle.standardError)

private struct FileHandleOutputStream: TextOutputStream {
    let fileHandle: FileHandle

    func write(_ string: String) {
        fileHandle.write(Data(string.utf8))
    }
}
