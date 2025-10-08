import Foundation

/// Workspace state stored in ~/.akashica/workspaces/{profile}/state.json
public struct WorkspaceState: Codable {
    public let version: String
    public let profile: String
    public let workspaceId: String  // Canonical format: @1045$ws_a3f2b8d9
    public let baseCommit: String   // @1045
    public var virtualCwd: String   // Repository virtual CWD: /docs/reports
    public let created: Date
    public var lastUsed: Date
    public var view: ViewState

    public init(
        version: String = "1.0",
        profile: String,
        workspaceId: String,
        baseCommit: String,
        virtualCwd: String = "/",
        created: Date = Date(),
        lastUsed: Date = Date(),
        view: ViewState = ViewState()
    ) {
        self.version = version
        self.profile = profile
        self.workspaceId = workspaceId
        self.baseCommit = baseCommit
        self.virtualCwd = virtualCwd
        self.created = created
        self.lastUsed = lastUsed
        self.view = view
    }

    public struct ViewState: Codable {
        public var active: Bool
        public var commit: String?
        public var startedAt: Date?

        public init(
            active: Bool = false,
            commit: String? = nil,
            startedAt: Date? = nil
        ) {
            self.active = active
            self.commit = commit
            self.startedAt = startedAt
        }
    }

    /// Update last used timestamp
    public mutating func touch() {
        self.lastUsed = Date()
    }

    /// Enter view mode
    public mutating func enterView(commit: String) {
        self.view = ViewState(
            active: true,
            commit: commit,
            startedAt: Date()
        )
    }

    /// Exit view mode
    public mutating func exitView() {
        self.view = ViewState(active: false)
    }
}
