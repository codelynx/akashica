import ArgumentParser
import Foundation

@available(macOS 10.15, *)
@main
struct AkashicaCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "akashica",
        abstract: "Content management system with tombstone-based deletion",
        version: "0.1.0",
        subcommands: [
            Init.self,
            Status.self,
            Commit.self,
            Checkout.self,
            Log.self,
            Branch.self,
            Diff.self,
            Scrub.self
        ]
    )
}
