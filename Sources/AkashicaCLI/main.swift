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
            Checkout.self,
            Commit.self,
            Status.self,
            Diff.self,
            Log.self,
            Branch.self,
            Scrub.self,
            // Virtual filesystem commands
            Ls.self,
            Cat.self,
            Cd.self,
            Pwd.self,
            Cp.self,
            Rm.self,
            Mv.self
        ]
    )
}
