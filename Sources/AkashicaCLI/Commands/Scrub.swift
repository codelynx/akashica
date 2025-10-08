import ArgumentParser
import Foundation
import Akashica

struct Scrub: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List tombstones (deleted content audit records)"
    )

    @Option(name: .long, help: "Profile name (defaults to AKASHICA_PROFILE environment variable)")
    var profile: String?

    func run() async throws {
        let context = try await CommandContext.resolve(profileFlag: profile)

        // Get tombstones with metadata from repository
        let tombstones = try await context.repository.listScrubbedContent()

        if tombstones.isEmpty {
            print("No tombstoned content to scrub")
            return
        }

        // Display tombstone details
        print("Tombstoned content (already deleted, metadata preserved):")
        print("")

        let sorted = tombstones.sorted { $0.0.value < $1.0.value }
        for (hash, tombstone) in sorted {
            let date = formatDate(tombstone.timestamp)
            print("  \(hash.value)")
            print("    Deleted: \(date)")
            print("    Reason: \(tombstone.reason)")
            print("    By: \(tombstone.deletedBy)")
            if let size = tombstone.originalSize {
                print("    Original size: \(size) bytes")
            }
        }
        print("")
        print("Total: \(tombstones.count) tombstone(s)")
        print("")
        print("Note: Content is already deleted. Tombstones serve as audit records.")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
