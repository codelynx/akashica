import ArgumentParser
import Foundation
import Akashica

struct Scrub: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List tombstones (deleted content audit records)"
    )

    @OptionGroup var storage: StorageOptions

    func run() async throws {
        let config = storage.makeConfig()

        // Create validated storage (efficient - one S3 adapter creation)
        let storage = try await config.createValidatedStorage()

        // Get tombstones (content hashes that have been deleted)
        let tombstoneHashes = try await storage.listTombstones()

        if tombstoneHashes.isEmpty {
            print("No tombstoned content to scrub")
            return
        }

        // Read tombstone metadata to show details
        print("Tombstoned content (already deleted, metadata preserved):")
        print("")
        for hash in tombstoneHashes.sorted(by: { $0.value < $1.value }) {
            // Try to read tombstone metadata if available
            if let tombstone = try? await storage.readTombstone(hash: hash) {
                let date = formatDate(tombstone.timestamp)
                print("  \(hash.value)")
                print("    Deleted: \(date)")
                print("    Reason: \(tombstone.reason)")
                print("    By: \(tombstone.deletedBy)")
                if let size = tombstone.originalSize {
                    print("    Original size: \(size) bytes")
                }
            } else {
                print("  \(hash.value)")
            }
        }
        print("")
        print("Total: \(tombstoneHashes.count) tombstone(s)")
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
