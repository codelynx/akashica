import ArgumentParser
import Foundation
import Akashica

struct Log: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show commit logs"
    )

    @OptionGroup var storage: StorageOptions

    @Option(name: .long, help: "Branch name")
    var branch: String = "main"

    @Option(name: .long, help: "Number of commits to show")
    var limit: Int = 10

    func run() async throws {
        let config = storage.makeConfig()

        // Create validated repository (efficient - one S3 adapter creation)
        let repo = try await config.createValidatedRepository()
        let history = try await repo.commitHistory(branch: branch, limit: limit)

        for (commit, metadata) in history {
            let date = formatDate(metadata.timestamp)
            print("\u{001B}[33mcommit \(commit.value)\u{001B}[0m")  // Yellow
            print("Author: \(metadata.author)")
            print("Date:   \(date)")
            print("")
            print("    \(metadata.message)")
            print("")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
