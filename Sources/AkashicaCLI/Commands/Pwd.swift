import ArgumentParser
import Foundation

struct Pwd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print virtual working directory"
    )

    @Option(name: .long, help: "Profile name (defaults to AKASHICA_PROFILE environment variable)")
    var profile: String?

    func run() async throws {
        let context = try await CommandContext.resolve(profileFlag: profile)

        // Print virtual CWD from workspace state
        let cwd = context.virtualCwd
        print(cwd.pathString.isEmpty ? "/" : cwd.pathString)
    }
}
