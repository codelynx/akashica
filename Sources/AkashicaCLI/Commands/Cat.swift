import ArgumentParser
import Foundation
import Akashica

struct Cat: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Display file contents from virtual filesystem"
    )

    @OptionGroup var storage: StorageOptions

    @Argument(help: "File path")
    var path: String

    func run() async throws {
        let config = storage.makeConfig()

        // Get current workspace
        guard let workspace = try config.currentWorkspace() else {
            print("Error: Not in a workspace. Use 'akashica checkout' to create one.")
            throw ExitCode.failure
        }

        // Create session
        let repo = try await config.createValidatedRepository()
        let session = await repo.session(workspace: workspace)

        // Resolve path (relative to virtual CWD)
        let vctx = config.virtualContext()
        let targetPath = vctx.resolvePath(path)

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
