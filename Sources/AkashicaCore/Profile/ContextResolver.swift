import Foundation

/// Resolves Akashica context from environment and profile configuration
public actor ContextResolver {
    private let profileManager: ProfileManager
    private let stateManager: WorkspaceStateManager

    public init(
        profileManager: ProfileManager? = nil,
        stateManager: WorkspaceStateManager? = nil
    ) {
        self.profileManager = profileManager ?? ProfileManager()
        self.stateManager = stateManager ?? WorkspaceStateManager()
    }

    /// Resolution source
    public enum Source {
        case commandLine(profile: String)
        case environment(profile: String)
    }

    /// Resolved context
    public struct Context {
        public let profile: ProfileConfig
        public let workspace: WorkspaceState
        public let source: Source

        public init(profile: ProfileConfig, workspace: WorkspaceState, source: Source) {
            self.profile = profile
            self.workspace = workspace
            self.source = source
        }
    }

    // MARK: - Resolve Context

    /// Resolve Akashica context from command-line flag or environment variable
    ///
    /// Priority:
    /// 1. Command-line --profile flag
    /// 2. AKASHICA_PROFILE environment variable
    /// 3. Error (no default profile)
    public func resolveContext(commandLineProfile: String?) async throws -> Context {
        let profileName: String
        let source: Source

        // 1. Command-line flag (highest priority)
        if let profile = commandLineProfile {
            profileName = profile
            source = .commandLine(profile: profile)
        }
        // 2. Environment variable
        else if let envProfile = ProcessInfo.processInfo.environment["AKASHICA_PROFILE"] {
            profileName = envProfile
            source = .environment(profile: envProfile)
        }
        // 3. Error - no default profile
        else {
            throw ContextError.noProfileSpecified
        }

        // Load profile configuration
        let profileConfig = try await profileManager.loadProfile(name: profileName)

        // Load workspace state
        let workspaceState = try await stateManager.loadState(profile: profileName)

        return Context(
            profile: profileConfig,
            workspace: workspaceState,
            source: source
        )
    }
}

// MARK: - Errors

public enum ContextError: Error, CustomStringConvertible {
    case noProfileSpecified

    public var description: String {
        switch self {
        case .noProfileSpecified:
            return """
            No Akashica profile specified.

            Set active profile:
              $ export AKASHICA_PROFILE=<name>
              $ akashica --profile <name> status

            Or create a new profile:
              $ akashica init --profile <name> <storage-path>
            """
        }
    }
}
