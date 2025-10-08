import Foundation

/// Manages workspace state in ~/.akashica/workspaces/{profile}/
public actor WorkspaceStateManager {
    private let workspacesDir: URL

    public init(workspacesDir: URL? = nil) {
        if let dir = workspacesDir {
            self.workspacesDir = dir
        } else {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            self.workspacesDir = homeDir
                .appendingPathComponent(".akashica")
                .appendingPathComponent("workspaces")
        }
    }

    // MARK: - Load State

    public func loadState(profile: String) throws -> WorkspaceState {
        let path = statePath(for: profile)

        guard FileManager.default.fileExists(atPath: path.path) else {
            throw WorkspaceError.stateNotFound(profile)
        }

        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkspaceState.self, from: data)
    }

    // MARK: - Save State

    public func saveState(_ state: WorkspaceState, overwrite: Bool = false) throws {
        let profileDir = workspacesDir.appendingPathComponent(state.profile)
        let path = profileDir.appendingPathComponent("state.json")

        // Check if state already exists
        if !overwrite && FileManager.default.fileExists(atPath: path.path) {
            throw WorkspaceError.stateAlreadyExists(state.profile)
        }

        // Create directory if needed
        try FileManager.default.createDirectory(
            at: profileDir,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: path)
    }

    // MARK: - Delete State

    public func deleteState(profile: String) throws {
        let profileDir = workspacesDir.appendingPathComponent(profile)

        guard FileManager.default.fileExists(atPath: profileDir.path) else {
            throw WorkspaceError.stateNotFound(profile)
        }

        try FileManager.default.removeItem(at: profileDir)
    }

    // MARK: - State Exists

    public func stateExists(profile: String) -> Bool {
        let path = statePath(for: profile)
        return FileManager.default.fileExists(atPath: path.path)
    }

    // MARK: - Update State

    public func updateState(profile: String, _ update: (inout WorkspaceState) -> Void) throws {
        var state = try loadState(profile: profile)
        update(&state)
        state.touch()
        try saveState(state, overwrite: true)  // Always overwrite when updating
    }

    // MARK: - Helpers

    private func statePath(for profile: String) -> URL {
        workspacesDir
            .appendingPathComponent(profile)
            .appendingPathComponent("state.json")
    }
}

// MARK: - Errors

public enum WorkspaceError: Error, CustomStringConvertible {
    case stateNotFound(String)
    case stateAlreadyExists(String)
    case invalidWorkspaceId(String)

    public var description: String {
        switch self {
        case .stateNotFound(let profile):
            return "Workspace state for profile '\(profile)' not found. Initialize the profile first with 'akashica init'."
        case .stateAlreadyExists(let profile):
            return "Workspace state for profile '\(profile)' already exists. This prevents accidental data loss. Delete the profile first if you want to reinitialize."
        case .invalidWorkspaceId(let id):
            return "Invalid workspace ID format: '\(id)'. Expected format: @<commit>$<suffix>"
        }
    }
}
