import ArgumentParser
import Foundation
import Akashica

struct Branch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List branches"
    )

    @OptionGroup var storage: StorageOptions

    func run() async throws {
        let config = storage.makeConfig()

        // Create validated repository (efficient - one S3 adapter creation)
        let repo = try await config.createValidatedRepository()
        let branches = try await repo.branches()

        if branches.isEmpty {
            print("No branches found")
            return
        }

        for branch in branches.sorted() {
            print("  \(branch)")
        }
    }
}
