import ArgumentParser
import Foundation
import Akashica

struct Branch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage branches",
        subcommands: [
            List.self,
            Reset.self
        ],
        defaultSubcommand: List.self
    )
}

// MARK: - Branch List

extension Branch {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all branches"
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
}

// MARK: - Branch Reset

extension Branch {
    struct Reset: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reset",
            abstract: "Reset branch pointer to a specific commit"
        )

        @OptionGroup var storage: StorageOptions

        @Argument(help: "Branch name to reset")
        var branchName: String

        @Option(name: .long, help: "Target commit to reset to (e.g., '@1020')")
        var to: String

        @Flag(name: .long, help: "Force reset to non-ancestor commit (skips safety checks)")
        var force: Bool = false

        func run() async throws {
            let config = storage.makeConfig()

            // Parse target commit ID
            guard to.hasPrefix("@") else {
                print("Error: Commit ID must start with '@' (e.g., '@1020')")
                throw ExitCode.failure
            }

            let targetCommit = CommitID(value: to)

            // Create validated repository
            let repo = try await config.createValidatedRepository()

            // Get current commit for display (may throw if branch doesn't exist)
            let currentCommit: CommitID
            do {
                currentCommit = try await repo.currentCommit(branch: branchName)
            } catch {
                // Branch doesn't exist - storage throws raw Foundation error
                print("Error: Branch '\(branchName)' not found")
                throw ExitCode.failure
            }

            // Perform reset
            do {
                try await repo.resetBranch(name: branchName, to: targetCommit, force: force)
            } catch AkashicaError.branchNotFound(let name) {
                print("Error: Branch '\(name)' not found")
                throw ExitCode.failure
            } catch AkashicaError.commitNotFound(let commit) {
                print("Error: Commit '\(commit.value)' not found")
                throw ExitCode.failure
            } catch AkashicaError.nonAncestorReset(let branch, let current, let target) {
                print("Error: Cannot reset branch '\(branch)' to \(target.value)")
                print("Reason: \(target.value) is not an ancestor of current head \(current.value)")
                print("")
                print("To force reset to an unrelated commit:")
                print("  akashica branch reset \(branch) --to \(target.value) --force")
                throw ExitCode.failure
            }

            // Success message
            print("Reset branch '\(branchName)' from \(currentCommit.value) to \(targetCommit.value)")

            if force {
                print("")
                print("Note: Used --force flag. Branch history may have diverged.")
            }
        }
    }
}
