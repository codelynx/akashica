# Session-First Architecture

**Version:** 1.0.0
**Status:** Design Proposal
**Date:** 2025-10-07

## Overview

This document proposes a **session-first architecture** where `AkashicaSession` becomes the primary interface for all operations, unifying CLI commands and programmatic API usage. This architectural shift ensures identical behavior across all interfaces and enables advanced workflows like session persistence, collaboration, and scripting.

## Core Insight

If `AkashicaSession` metadata can be serialized, we can create a session-centric architecture where:

1. **CLI commands become thin wrappers** around session operations
2. **All operations go through session**, ensuring identical behavior
3. **Session descriptors can be saved/restored**, enabling advanced workflows

**Important**: We serialize session *metadata* (workspace ID, storage config, virtual CWD), not the full actor state (which contains non-Codable resources like network clients and credentials).

## Current vs. Proposed Architecture

### Current Architecture
```swift
// CLI command → direct repository manipulation
struct Cp: AsyncParsableCommand {
    func run() async throws {
        let repo = try Repository.open(...)
        let session = try repo.createWorkspaceSession(...)
        try await session.writeFile(...)
    }
}
```

**Problems:**
- Each command re-implements repository opening logic
- Path resolution scattered across commands
- Hard to guarantee identical behavior between CLI and API
- Difficult to test without real storage

### Proposed Architecture: Session-First
```swift
// 1. Session becomes the primary interface (existing actor API)
protocol AkashicaSession {
    func readFile(_ path: RepositoryPath) async throws -> Data
    func writeFile(_ path: RepositoryPath, data: Data) async throws
    func listDirectory(_ path: RepositoryPath) async throws -> [DirectoryEntry]
    func deleteFile(_ path: RepositoryPath) async throws
    func moveFile(from: RepositoryPath, to: RepositoryPath) async throws
}

// 2. SessionDescriptor holds serializable metadata
struct SessionDescriptor: Codable {
    let type: SessionType
    let workspaceID: WorkspaceID?
    let commitID: CommitID?
    let branchName: String?
    let storageConfigRef: String  // Reference to config, NOT credentials
    let virtualCWD: String
    let createdAt: Date
    let expiresAt: Date?
}

// 3. CLI commands delegate to session
struct Cp: AsyncParsableCommand {
    func run() async throws {
        // Parse URI to determine session type
        let uri = try AkaURI.parse(destination)

        // Get or create session (session factory handles scope → session mapping)
        let session = try await config.getSession(for: uri.scope)

        // Delegate to session
        try await session.writeFile(uri.path, data: localData)
    }
}
```

**Benefits:**
- Single code path for all operations
- Guaranteed consistency across CLI and API
- Easy to test with mock sessions
- Foundation for advanced workflows

## Key Benefits

### 1. Identical Behavior Across Interfaces

```swift
// CLI
$ akashica cp /tmp/file.txt aka:///reports/file.txt

// Programmatic (Swift API)
let session = try await config.getSession(for: .currentWorkspace)
try await session.writeFile("/reports/file.txt", data: localData)

// Both execute EXACTLY the same session method
```

### 2. Session Persistence & Recovery

```swift
// Save session state
let sessionData = try session.save()
try sessionData.write(to: URL(fileURLWithPath: ".akashica/session"))

// Restore later (even on different machine!)
let session = try AkashicaSession.restore(from: sessionData)
try await session.writeFile(...) // Continue where you left off
```

### 3. Remote Sessions & Collaboration

```swift
// User A creates session
let session = try await repo.createWorkspaceSession(...)
let sessionToken = try session.serialize()
sendToUserB(sessionToken)

// User B uses same session
let session = try AkashicaSession.restore(from: sessionToken)
try await session.writeFile(...) // Writes to same workspace!
```

### 4. Batch Operations & Transactions

```swift
// Create session once, execute multiple operations
let session = try await config.getSession(for: .currentWorkspace)

// All operations use same session context
try await session.writeFile(aka:///file1.txt, data: data1)
try await session.writeFile(aka:///file2.txt, data: data2)
try await session.deleteFile(aka:///old.txt)

// Commit all at once
try await repo.publishWorkspace(session.workspaceID, ...)
```

### 5. Session Scope Enforcement

```swift
// Session enforces read-only for branches/commits
let branchSession = try await config.getSession(for: .branch("main"))
try await branchSession.writeFile(...) // ❌ Throws error: "Session is read-only"

let workspaceSession = try await config.getSession(for: .currentWorkspace)
try await workspaceSession.writeFile(...) // ✅ Works
```

### 6. Easy Testing & Mocking

```swift
// Easy to mock session for tests
class MockSession: AkashicaSession {
    var files: [RepositoryPath: Data] = [:]

    func writeFile(_ path: RepositoryPath, data: Data) async throws {
        files[path] = data
    }
}

// Test commands without real storage
let mockSession = MockSession()
try await Cp.execute(session: mockSession, ...)
```

## Implementation Strategy

### Phase 2a: Session Factory (MVP)

Create a factory method that maps URI scopes to sessions:

```swift
// Sources/AkashicaCLI/Config+Session.swift
extension Config {
    /// Get or create a session for the given URI scope
    /// - Returns: Session appropriate for the scope (workspace/branch/commit)
    func getSession(for scope: AkaURI.Scope) async throws -> any AkashicaSession {
        let repo = try createValidatedRepository()

        switch scope {
        case .currentWorkspace:
            // Get current workspace ID
            guard let workspaceID = try currentWorkspace() else {
                throw AkashicaError.noWorkspace(
                    "No active workspace. Run 'akashica checkout <branch>' first."
                )
            }
            return try await repo.createWorkspaceSession(workspaceID: workspaceID)

        case .branch(let name):
            // Read branch pointer, create commit session
            let branchPointer = try await repo.storage.readBranchPointer(name: name)
            return try await repo.createCommitSession(commitID: branchPointer.commitID)

        case .commit(let commitID):
            // Create commit session directly
            return try await repo.createCommitSession(commitID: commitID)
        }
    }

    /// Resolve URI path to absolute RepositoryPath
    /// - Handles relative paths from virtual CWD
    func resolvePathFromURI(_ uri: AkaURI) throws -> RepositoryPath {
        if uri.isRelativePath {
            // Relative: resolve from virtual CWD
            let vctx = virtualContext()
            return vctx.resolvePath(uri.path)
        } else {
            // Absolute or scoped: use as-is
            return RepositoryPath(string: uri.path)
        }
    }
}
```

### Phase 2b: Command Wrapper Pattern

All commands follow the same simple pattern:

```swift
// Upload example (Cp command)
struct Cp: AsyncParsableCommand {
    @Argument var source: String
    @Argument var destination: String

    func run() async throws {
        let config = try Config.load()

        // Determine if paths are local or remote
        let srcIsRemote = AkaURI.isAkaURI(source)
        let dstIsRemote = AkaURI.isAkaURI(destination)

        switch (srcIsRemote, dstIsRemote) {
        case (false, true):
            try await uploadFile(config: config)
        case (true, false):
            try await downloadFile(config: config)
        case (true, true):
            throw AkashicaError.unsupportedOperation("Remote-to-remote copy not yet supported")
        case (false, false):
            throw AkashicaError.unsupportedOperation("Both paths are local. Use 'cp' command.")
        }
    }

    private func uploadFile(config: Config) async throws {
        // Parse destination URI
        let uri = try AkaURI.parse(destination)

        // Validate writable
        guard uri.isWritable else {
            throw AkashicaError.readOnlyScope(
                "Cannot write to read-only scope: \(uri.scopeDescription)"
            )
        }

        // Get session and resolve path
        let session = try await config.getSession(for: uri.scope)
        let remotePath = try config.resolvePathFromURI(uri)

        // Read local file
        let localURL = URL(fileURLWithPath: source)
        let data = try Data(contentsOf: localURL)

        // Delegate to session
        try await session.writeFile(remotePath, data: data)

        print("Uploaded: \(source) → \(uri.toString())")
    }
}

// Read-only example (Cat command)
struct Cat: AsyncParsableCommand {
    @Argument var path: String

    func run() async throws {
        let config = try Config.load()
        let uri = try AkaURI.parse(path)
        let session = try await config.getSession(for: uri.scope)
        let resolvedPath = try config.resolvePathFromURI(uri)

        let data = try await session.readFile(resolvedPath)
        FileHandle.standardOutput.write(data)
    }
}

// Write example (Rm command)
struct Rm: AsyncParsableCommand {
    @Argument var path: String

    func run() async throws {
        let config = try Config.load()
        let uri = try AkaURI.parse(path)

        // Validate writable
        guard uri.isWritable else {
            throw AkashicaError.readOnlyScope(
                "Cannot delete from read-only scope: \(uri.scopeDescription)"
            )
        }

        let session = try await config.getSession(for: uri.scope)
        let resolvedPath = try config.resolvePathFromURI(uri)

        try await session.deleteFile(resolvedPath)
        print("Deleted: \(uri.toString())")
    }
}
```

**Pattern**: 3-5 lines of boilerplate, then delegate to session.

### Phase 2c: Unified Command Pattern

Every command follows the same structure:

1. Load config
2. Parse URI(s)
3. Get session(s) via factory
4. Resolve path(s)
5. Delegate to session
6. Print result

## Advanced Use Cases

### 1. Offline Editing

```swift
// Save workspace session to laptop
let session = try await repo.createWorkspaceSession(...)
let sessionData = try session.save()
try sessionData.write(to: "~/workspace-backup.aka")

// Disconnect from S3, edit files offline
// ...later, restore and sync
let session = try AkashicaSession.restore(from: backupData)
try await repo.publishWorkspace(session.workspaceID, ...)
```

### 2. Multi-User Collaboration

```swift
// Team lead creates workspace, shares session token
let session = try await repo.createWorkspaceSession(...)
let token = try session.serialize() // base64 encoded

// Team members restore session and contribute
let session = try AkashicaSession.restore(from: token)
try await session.writeFile(...) // All write to same workspace
```

### 3. Scripting & Automation

```swift
#!/usr/bin/env swift
import Akashica

let config = try Config.load()
let session = try await config.getSession(for: .currentWorkspace)

// Batch upload
for file in Directory.contents(of: "/local/photos") {
    let data = try Data(contentsOf: file)
    try await session.writeFile("/photos/\(file.name)", data: data)
}

try await repo.publishWorkspace(...)
```

### 4. Session-Based Web API

```swift
// REST API endpoint
app.post("/api/files") { req async throws -> Response in
    let sessionToken = try req.headers["X-Session-Token"].unwrap()
    let session = try AkashicaSession.restore(from: sessionToken)

    let file = try req.content.decode(FileUpload.self)
    try await session.writeFile(file.path, data: file.data)

    return Response(status: .created)
}
```

## Future Phases

### Phase 4: Session Caching

Store session metadata in `.akashica/sessions/` for performance:

```json
// .akashica/sessions/workspace-<id>.json
{
  "type": "workspace",
  "workspaceID": "@1234$a1b3",
  "storage": { "bucket": "...", "region": "..." },
  "virtualCWD": "/japan/tokyo",
  "createdAt": "2025-10-07T14:52:19Z",
  "expiresAt": "2025-10-07T16:52:19Z"
}
```

**Implementation**:
```swift
extension Config {
    func getSession(for scope: AkaURI.Scope) async throws -> any AkashicaSession {
        // Check cache first
        if let cached = try loadCachedSession(for: scope), !cached.isExpired {
            return cached
        }

        // Create new session
        let session = try await createNewSession(for: scope)

        // Cache for next time
        try cacheSession(session, for: scope)

        return session
    }
}
```

### Phase 5: SessionDescriptor Enhancement

Enhance the SessionDescriptor with additional features:

```swift
extension SessionDescriptor {
    // Encryption for sharing across machines
    func encrypt(using key: SymmetricKey) throws -> Data {
        let jsonData = try JSONEncoder().encode(self)
        return try ChaChaPoly.seal(jsonData, using: key).combined
    }

    static func decrypt(from data: Data, using key: SymmetricKey) throws -> SessionDescriptor {
        let sealedBox = try ChaChaPoly.SealedBox(combined: data)
        let jsonData = try ChaChaPoly.open(sealedBox, using: key)
        return try JSONDecoder().decode(SessionDescriptor.self, from: jsonData)
    }

    // Validation
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }

    // Shareable token (base64 + encryption)
    func toShareableToken(key: SymmetricKey) throws -> String {
        let encrypted = try encrypt(using: key)
        return encrypted.base64EncodedString()
    }
}
```

**Security notes**:
- Encryption mandatory for cross-machine sharing
- Use `CryptoKit` for encryption (ChaCha20-Poly1305)
- Store encryption keys securely (Keychain, env vars, not in config)
- Session tokens are opaque, time-limited, single-use preferred

### Phase 6: Session Locking (Concurrency Control)

For shared workspace access:

```swift
// Acquire lock when resuming session
extension Repository {
    func resumeSession(from descriptor: SessionDescriptor, acquireLock: Bool = true) async throws -> any AkashicaSession {
        if acquireLock && descriptor.type == .workspace {
            // Try to acquire lock in storage
            let lockKey = "locks/workspace-\(descriptor.workspaceID!.fullReference)"
            let lockData = LockDescriptor(
                acquiredBy: ProcessInfo.processInfo.hostName,
                acquiredAt: Date(),
                ttl: 3600 // 1 hour
            )

            let acquired = try await storage.tryAcquireLock(key: lockKey, data: lockData)
            guard acquired else {
                throw AkashicaError.workspaceLocked("Workspace is locked by another process")
            }
        }

        return try await createSession(from: descriptor)
    }
}
```

**Lock implementation** (S3):
- Use conditional PutObject with `If-None-Match: *` (only create if doesn't exist)
- Store lock with TTL metadata
- Background cleanup process deletes expired locks

## Critical Design Considerations

### 1. Serialization Scope: Metadata Only

**Key principle**: We serialize session **metadata** (SessionDescriptor), not the full `AkashicaSession` actor.

**Why?** Actors contain non-Codable resources:
- Network clients (URLSession, S3Client)
- Open file handles
- In-memory caches
- Live credentials

**Solution**: `SessionDescriptor` contains only:
- Session type (workspace/branch/commit)
- IDs (workspace ID, commit ID, branch name)
- Storage config **reference** (not credentials)
- Virtual CWD
- Timestamps (created, expires)

**Rehydration**: `Repository.resumeSession(descriptor:)` recreates a fresh session actor from the descriptor.

### 2. Credential Hygiene & Security

**Critical security principle**: Credentials NEVER go into session descriptors.

**Storage locations**:
- ✅ **Credentials**: `.akashica/config.json` (local only, gitignored)
- ✅ **Session descriptors**: `.akashica/sessions/*.json` (references config)
- ❌ **NEVER**: Credentials in serialized descriptors

**Sharing sessions safely**:
```swift
// ❌ DON'T: Share full config with credentials
let descriptor = SessionDescriptor(storageConfig: config.storage) // UNSAFE!

// ✅ DO: Share descriptor with config reference
let descriptor = SessionDescriptor(
    storageConfigRef: "default",  // References receiver's own .akashica/config.json
    workspaceID: workspace.id,
    ...
)
```

**Encryption requirements**:
- Session descriptors shared across machines: **MUST encrypt** (contains workspace IDs, bucket names)
- Local cache in `.akashica/sessions/`: **RECOMMENDED encrypt** for sensitive projects
- Session tokens for collaboration: **MUST encrypt + TTL** (e.g., 1-hour max)

**Best practices**:
1. Never log or print session descriptors
2. Add `.akashica/sessions/` to `.gitignore`
3. Use short TTLs (1-2 hours) for shared descriptors
4. Rotate workspace IDs if descriptors leak
5. Consider encryption-at-rest for local cache

### 3. Workspace Concurrency & Conflict Resolution

**MVP approach** (Phases 2-3):
- **Model**: Last-writer-wins via storage layer CAS
- **Assumption**: One user per workspace at a time
- **Behavior**: If two users modify same workspace, last commit wins
- **Detection**: Current CAS mechanism catches concurrent branch updates

**Future approach** (Phase 6+):
- **Optimistic locking**: Acquire lock on session resume
- **Lock storage**: S3 object with conditional PutObject (`If-None-Match: *`)
- **Lock TTL**: 1 hour default, auto-expires if client crashes
- **Lock refresh**: Background task refreshes every 30 minutes
- **Conflict handling**: Clear error message if lock held by another user

**Clock skew considerations**:
- TTL > 1 hour: Robust to typical clock skew (< 5 minutes)
- For shorter TTLs: Use storage-provided timestamps (S3 LastModified)
- Never rely on client clock for lock expiration

**Collaboration model**:
```
User A                          User B
------------------------------------
1. Checkout main
2. Get workspace W1
3. Share descriptor D1 -------> 4. Resume session from D1
5. Write file1.txt              6. Write file2.txt
7. Both write to SAME workspace W1
8. Commit (whoever commits first wins)
```

**Key insight**: Sharing a descriptor means **collaborating in same workspace**, not creating separate workspaces. This is powerful but requires coordination.

### 4. Session Lifecycle

**CLI commands** (simple):
- Create session at command start
- Use for single operation
- Discard on exit

**Interactive shell** (future):
- Create session on first use
- Keep singleton per scope
- Persist across commands
- Close on shell exit

**Long-running services** (future):
- Pool of sessions
- TTL-based eviction
- Background refresh

### 2. Session Semantics in Library

`AkashicaSession` is currently an actor holding:
- Storage adapter (non-Codable)
- Workspace/commit ID (Codable)
- In-memory caches (non-Codable)
- Network clients (non-Codable)

**Solution**: Serialize only the *descriptor*, not the actor itself.

### 3. Security & Credentials

Session descriptors may contain:
- S3 bucket names
- Region information
- Workspace IDs

**Recommendations**:
- Credentials stay in `.akashica/config.json` (never serialized)
- Session descriptors reference config, don't duplicate credentials
- Encrypt serialized descriptors if sharing across machines
- Add TTL to prevent indefinite access

### 4. Concurrency Model

**MVP approach** (Phase 2-3):
- Assume one user per workspace at a time
- No locking mechanism
- Last write wins (via storage layer)

**Future approach** (Phase 6):
- Optimistic locking with CAS in storage layer
- Lock acquisition on session resume
- TTL-based lock expiration
- Lock refresh for long-running operations

### 5. Backward Compatibility & SDK Migration

This architecture **builds on** the existing library with **zero breaking changes**:

**Library layer** (unchanged):
- `Repository` actor remains the factory for sessions
- `AkashicaSession` protocol unchanged
- All existing methods work as-is
- Storage adapters unchanged

**CLI layer** (new):
- Adds `Config.getSession(for:)` convenience method
- Commands become thin wrappers
- No impact on library consumers

**SDK Migration Path**:

**Before** (direct repository usage):
```swift
import Akashica

let repo = try await Repository.open(storage: storage)
let workspace = try await repo.createWorkspace(basedOn: commitID)
let session = try await repo.createWorkspaceSession(workspaceID: workspace.id)
try await session.writeFile("/path/to/file", data: data)
try await repo.publishWorkspace(workspace.id, to: "main", message: "Update")
```

**After** (session-first, recommended):
```swift
import Akashica
import AkashicaCLI  // For Config helpers

let config = try Config.load()
let session = try await config.getSession(for: .currentWorkspace)
try await session.writeFile("/path/to/file", data: data)
// Commit handled by CLI or explicit repo.publishWorkspace
```

**Migration timeline**:
- **Phase 2-3**: CLI adopts session-first, library unchanged
- **Phase 4-5**: Add `Config.getSession` as library convenience method (optional)
- **Future**: Document recommended patterns for SDK users
- **No deprecations**: Old patterns continue to work indefinitely

**SDK user benefits**:
- Easier session creation (no manual workspace setup)
- Consistent with CLI behavior
- Access to session caching (Phase 4+)
- Optional adoption (old code still works)

**Key principle**: Additive changes only, no breaking changes.

## Comparison with Git

| Aspect | Git | Akashica (Session-First) |
|--------|-----|---------------------------|
| **Primary interface** | Working directory + index | Session |
| **State location** | `.git/` + working tree | Session (in-memory or serialized) |
| **Remote operations** | Explicit (push/pull) | Transparent (session-based) |
| **Collaboration** | Clone → modify → push | Share session → collaborate |
| **Offline mode** | Full clone required | Lightweight session backup |
| **Consistency** | Command-specific logic | Single session path |
| **Testing** | Filesystem-dependent | Mockable sessions |

## Implementation Phases

### ✅ Phase 1: URI Parser (Complete)
- [x] AkaURI.swift with three formats
- [x] Design document (aka-uri-scheme.md)
- [x] All tests passing

### 🔄 Phase 2: Session Factory (In Progress)
- [ ] **Phase 2a**: Implement `Config.getSession(for:)`
- [ ] **Phase 2b**: Implement `Config.resolvePathFromURI(_:)`
- [ ] **Phase 2c**: Update Cp command with session-first pattern
- [ ] **Phase 2d**: Test with all URI scopes (workspace/branch/commit)

### 📋 Phase 3: Remaining Commands
- [ ] Update Cat, Ls, Cd, Rm, Mv with same pattern
- [ ] Verify identical behavior across commands
- [ ] Add integration tests

### 🚀 Phase 4: Session Caching
- [ ] Design cache structure (`.akashica/sessions/`)
- [ ] Implement cache read/write
- [ ] Add TTL and expiration
- [ ] Performance testing

### 📚 Phase 5: Documentation
- [ ] Update VIRTUAL_FILESYSTEM.md with session examples
- [ ] Add scripting guide
- [ ] Document session caching behavior

### 🧪 Phase 6: End-to-End Testing
- [ ] Test all commands with all URI scopes
- [ ] Test session caching
- [ ] Test error scenarios
- [ ] Performance benchmarks

### 🔮 Future: Advanced Features
- [ ] SessionDescriptor design & implementation
- [ ] Session serialization/deserialization
- [ ] Session locking for concurrency
- [ ] Web API integration
- [ ] Collaborative editing

## Success Metrics

1. **Code Simplicity**: Every command < 20 lines
2. **Consistency**: CLI and API use identical code paths
3. **Testability**: 100% command coverage with mock sessions
4. **Performance**: Session caching reduces latency by 50%+
5. **Extensibility**: New commands take < 30 minutes to implement

## Conclusion

The session-first architecture is a **paradigm shift** that transforms Akashica from a collection of CLI tools into a cohesive, session-centric platform. By making `AkashicaSession` the primary interface and introducing the `aka://` URI scheme for addressing, we achieve:

- **Unified abstraction**: Single code path for all operations
- **Advanced workflows**: Session persistence, collaboration, scripting
- **Simplified implementation**: 3-5 line command wrappers
- **Future-proof design**: Foundation for serialization, caching, locking

This is not just an implementation detail—it's the architectural key that unlocks Akashica's full potential.

---

**Built with** [Claude Code](https://claude.com/claude-code)
