import ArgumentParser
import Foundation
import AkashicaCore

struct Profile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage Akashica profiles",
        subcommands: [
            List.self,
            Show.self,
            Delete.self
        ],
        defaultSubcommand: List.self
    )
}

// MARK: - Profile List

extension Profile {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List all profiles"
        )

        func run() async throws {
            let profileManager = ProfileManager()
            let profiles = try await profileManager.listProfiles()

            if profiles.isEmpty {
                print("No profiles found.")
                print("")
                print("Create a profile:")
                print("  $ akashica init --profile <name> <storage-path>")
                return
            }

            // Get active profile from environment
            let activeProfile = ProcessInfo.processInfo.environment["AKASHICA_PROFILE"]

            for profile in profiles.sorted(by: { $0.name < $1.name }) {
                let marker = (profile.name == activeProfile) ? "* " : "  "
                let storageInfo = formatStorage(profile.storage)
                print("\(marker)\(profile.name) (\(storageInfo))")
            }

            if let active = activeProfile {
                print("")
                print("Active profile: \(active)")
            } else {
                print("")
                print("No active profile. Set with:")
                print("  $ export AKASHICA_PROFILE=<name>")
            }
        }

        private func formatStorage(_ storage: ProfileConfig.StorageConfig) -> String {
            switch storage.type {
            case "local":
                return storage.path ?? "local"
            case "s3":
                if let bucket = storage.bucket {
                    if let prefix = storage.prefix, !prefix.isEmpty {
                        return "s3://\(bucket)/\(prefix)"
                    }
                    return "s3://\(bucket)"
                }
                return "s3"
            default:
                return storage.type
            }
        }
    }
}

// MARK: - Profile Show

extension Profile {
    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show profile details"
        )

        @Argument(help: "Profile name (defaults to active profile)")
        var profileName: String?

        func run() async throws {
            let profileManager = ProfileManager()
            let stateManager = WorkspaceStateManager()

            // Determine which profile to show
            let name: String
            if let specified = profileName {
                name = specified
            } else if let envProfile = ProcessInfo.processInfo.environment["AKASHICA_PROFILE"] {
                name = envProfile
            } else {
                print("Error: No profile specified and AKASHICA_PROFILE not set.")
                print("")
                print("Usage:")
                print("  $ akashica profile show <name>")
                print("  $ export AKASHICA_PROFILE=<name> && akashica profile show")
                throw ExitCode.failure
            }

            // Load profile
            let profile = try await profileManager.loadProfile(name: name)

            print("Profile: \(profile.name)")
            print("")
            print("Storage:")
            print("  Type: \(profile.storage.type)")
            switch profile.storage.type {
            case "local":
                print("  Path: \(profile.storage.path ?? "?")")
            case "s3":
                print("  Bucket: \(profile.storage.bucket ?? "?")")
                if let prefix = profile.storage.prefix {
                    print("  Prefix: \(prefix)")
                }
                if let region = profile.storage.region {
                    print("  Region: \(region)")
                }
            default:
                break
            }

            print("")
            print("Configuration:")
            print("  File: ~/.akashica/configurations/\(profile.name).json")
            print("  Created: \(formatDate(profile.created))")

            // Load workspace state if it exists
            if await stateManager.stateExists(profile: name) {
                let state = try await stateManager.loadState(profile: name)
                print("")
                print("Workspace State:")
                print("  ID: \(state.workspaceId)")
                print("  Base Commit: \(state.baseCommit)")
                print("  Virtual CWD: \(state.virtualCwd)")
                print("  Last Used: \(formatDate(state.lastUsed))")

                if state.view.active {
                    print("")
                    print("View Mode: Active")
                    if let commit = state.view.commit {
                        print("  Viewing: \(commit)")
                    }
                    if let startedAt = state.view.startedAt {
                        print("  Started: \(formatDate(startedAt))")
                    }
                }
            }
        }

        private func formatDate(_ date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            return formatter.string(from: date)
        }
    }
}

// MARK: - Profile Delete

extension Profile {
    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a profile"
        )

        @Argument(help: "Profile name to delete")
        var profileName: String

        @Flag(name: .long, help: "Skip confirmation prompt")
        var force: Bool = false

        func run() async throws {
            let profileManager = ProfileManager()
            let stateManager = WorkspaceStateManager()

            // Check if profile exists
            guard await profileManager.profileExists(name: profileName) else {
                print("Error: Profile '\(profileName)' not found.")
                throw ExitCode.failure
            }

            // Warn if deleting active profile
            if let activeProfile = ProcessInfo.processInfo.environment["AKASHICA_PROFILE"],
               activeProfile == profileName {
                print("Warning: Deleting active profile '\(profileName)'")
            }

            // Confirm deletion unless --force
            if !force {
                print("Delete profile '\(profileName)'? [y/N]: ", terminator: "")
                fflush(stdout)

                let response = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? "n"
                if response != "y" && response != "yes" {
                    print("Cancelled.")
                    throw ExitCode.success
                }
            }

            // Delete profile configuration
            try await profileManager.deleteProfile(name: profileName)
            print("✓ Deleted profile configuration: ~/.akashica/configurations/\(profileName).json")

            // Delete workspace state if it exists
            if await stateManager.stateExists(profile: profileName) {
                try await stateManager.deleteState(profile: profileName)
                print("✓ Deleted workspace state: ~/.akashica/workspaces/\(profileName)/")
            }

            print("")
            print("Profile '\(profileName)' deleted successfully.")

            // Reminder about repository data
            print("")
            print("Note: Repository data in storage was NOT deleted.")
            print("To delete repository data, manually remove the storage directory.")
        }
    }
}
