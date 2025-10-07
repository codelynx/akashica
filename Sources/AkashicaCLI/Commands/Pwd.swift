import ArgumentParser
import Foundation

struct Pwd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print virtual working directory"
    )

    @OptionGroup var storage: StorageOptions

    func run() async throws {
        let config = storage.makeConfig()

        // For S3 mode, just check if config looks valid (don't validate full repository)
        // For local mode, ensure .akashica exists
        if config.s3Bucket == nil && !config.isInRepository {
            print("Error: Not in an Akashica repository")
            print("Run 'akashica init' to initialize a repository")
            throw ExitCode.failure
        }

        // Get virtual CWD
        let vctx = config.virtualContext()
        let cwd = vctx.currentDirectory()

        // Print path (use "/" for root)
        print(cwd.pathString.isEmpty ? "/" : cwd.pathString)
    }
}
