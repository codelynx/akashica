# Separated Storage Architecture for Akashica

**Status**: Draft
**Version**: 0.10.0
**Date**: 2025-10-08
**Author**: Architecture Planning

## Overview

This proposal introduces a fundamental architectural change to Akashica: **separating the working directory from repository storage**. This enables:

- **Scalability**: Multi-TB repositories on NAS without filling working directories
- **Collaboration**: Multiple team members with independent workspaces pointing to shared storage
- **Flexibility**: Repository storage on reliable/backed-up volumes (NAS/S3) while working directories remain temporary

## Problem Statement

### Current Behavior (v0.9.0)

When choosing "Local filesystem" during `akashica init`, the repository storage is created directly in the current working directory:

```
~/projects/my-video-project/
├── .akashica/           # Workspace metadata
├── objects/             # Content-addressed objects (MIXED WITH WORKING DIR)
├── branches/            # Branch pointers (MIXED WITH WORKING DIR)
├── changeset/           # Commit metadata (MIXED WITH WORKING DIR)
└── myfile.txt           # User content
```

**Issues**:
1. Working directory and repository storage are co-located
2. Cannot point repository storage to large NAS drives
3. No support for multiple workspaces sharing the same repository
4. Repository grows unbounded in working directory

### Expected Behavior

**Working Directory** (temporary workspace):
- Temporary staging area for active work
- Workspace metadata pointing to repository location
- Cache for objects pulled from storage (future)
- **Ephemeral**: Can be empty between work sessions

**Repository Storage** (permanent, separate location):
- NAS drive: `/Volumes/NAS/akashica-repos/my-project`
- Separate disk: `/data/repos/my-project`
- S3: `s3://my-bucket/repos/my-project`
- Contains: objects, branches, changesets, manifests
- **Permanent**: All committed content lives here

## Architecture

### Directory Structure

```
Working Directory: ~/projects/my-video-project/
├── .akashica/
│   ├── config                    # Repository configuration
│   ├── workspace.json            # Workspace metadata
│   └── cache/                    # (future) Cached objects
├── video1.mp4                    # Temporary working file
└── notes.txt                     # Temporary working file

Repository Storage: /Volumes/NAS/akashica-repos/my-video-project/
├── .akashica-version             # Repository format version
├── objects/
│   └── a3/f2/b8d9...f9.dat      # Content-addressed objects
├── branches/
│   └── main.json                 # Branch pointers
└── changeset/
    └── @1001/
        ├── commit.json           # Commit metadata
        └── .dir                  # Root manifest
```

### Configuration Files

#### `.akashica/config` (Working Directory)

**Local storage**:
```json
{
  "version": "1.0",
  "repositoryId": "my-video-project",

  "storage": {
    "type": "local",
    "path": "/Volumes/NAS/akashica-repos/my-video-project"
  },

  "workspace": {
    "id": "@1045$ws_a3f2b8d9",
    "branch": "main",
    "baseCommit": "@1045",
    "created": "2025-10-08T10:30:00Z",
    "lastSync": "2025-10-08T14:22:00Z"
  },

  "view": {
    "active": false,
    "commit": null,
    "startedAt": null
  },

  "cache": {
    "enabled": true,
    "maxSize": "10GB",
    "currentSize": "2.3GB"
  }
}
```

**S3 storage**:
```json
{
  "version": "1.0",
  "repositoryId": "my-video-project",

  "storage": {
    "type": "s3",
    "bucket": "my-company-akashica",
    "prefix": "repos/my-video-project",
    "region": "us-west-2"
  },

  "workspace": {
    "id": "@1045$ws_a3f2b8d9",
    "branch": "main",
    "baseCommit": "@1045",
    "created": "2025-10-08T10:30:00Z",
    "lastSync": "2025-10-08T14:22:00Z"
  },

  "view": {
    "active": false,
    "commit": null,
    "startedAt": null
  },

  "cache": {
    "enabled": true,
    "maxSize": "50GB",
    "currentSize": "12.3GB"
  }
}
```

**Key Points**:
- `workspace.id`: Canonical `@{commit}${suffix}` format (e.g., `@1045$ws_a3f2b8d9`)
- `workspace.baseCommit`: Base commit this workspace is tracking
- `view.active`: Whether workspace is in view mode (read-only historical exploration)
- `cache`: Future support for local object cache

#### `.akashica-version` (Repository Storage)

```
1.0
```

Simple version marker for future migration detection. Existing repositories without this file default to version "1.0".

## User Experience

### 1. Create New Repository

```bash
$ cd ~/projects/new-project
$ akashica init

Storage path: /Volumes/NAS/repos/new-project
Checking repository...
✗ Repository not found at /Volumes/NAS/repos/new-project

Create new repository? [Y/n]: Y
Repository name [new-project]:

✓ Created repository at /Volumes/NAS/repos/new-project
✓ Initialized branch: main
✓ Attached workspace at ~/projects/new-project
```

**Explicit flags**:
```bash
# Force create (fail if exists)
$ akashica init --create --storage-path /Volumes/NAS/repos/new-project

# Interactive prompt skipped when flags provided
✓ Created repository at /Volumes/NAS/repos/new-project
✓ Attached workspace at ~/projects/new-project
```

### 2. Attach to Existing Repository

```bash
$ cd ~/projects/team-workspace
$ akashica init

Storage path: /Volumes/NAS/repos/video-campaign
Checking repository...
✓ Found existing repository: video-campaign (version 1.0)

Attach workspace to this repository? [Y/n]: Y

Available branches:
  * main (@1045)
    feature/intro (@1032)

Select branch [main]:

✓ Attached workspace to /Volumes/NAS/repos/video-campaign
✓ Workspace ready at ~/projects/team-workspace
✓ Branch: main (@1045)
```

**Explicit flags**:
```bash
# Force attach (fail if not exists)
$ akashica init --attach --storage-path /Volumes/NAS/repos/video-campaign

✓ Found existing repository: video-campaign (15 commits, 3 branches)
✓ Attached workspace at ~/projects/team-workspace
✓ Branch: main (@1045)
```

**Key Terminology**:
- **Attach** (not "clone"): No duplication occurs
- Repository stays in NAS/S3
- Workspace is lightweight (just `.akashica/` config)
- Files fetched on-demand when needed

### 3. Team Workflow

**Team lead creates repository**:
```bash
$ cd ~/projects/video-campaign
$ akashica init --create --storage-path /Volumes/NAS/repos/video-campaign

# Add files
$ cp ~/Desktop/intro.mp4 .
$ akashica commit -m "Add intro video"
✓ Committed @1001 to main

# Clean working directory (files safe in repository storage)
$ rm intro.mp4
```

**Team member attaches workspace**:
```bash
# Different working directory, same repository storage
$ mkdir ~/work/video-campaign
$ cd ~/work/video-campaign
$ akashica init --attach --storage-path /Volumes/NAS/repos/video-campaign

# Working directory is empty initially
$ ls
# (empty)

# Checkout files to work with them
$ akashica checkout main
✓ Fetched intro.mp4 from storage
✓ Working directory updated

$ ls
intro.mp4

# Make changes and commit
$ edit intro.mp4
$ akashica commit -m "Updated intro transitions"
✓ Committed @1002 to main
```

### 4. Cloud Storage Workflow

```bash
$ cd ~/projects/cloud-assets
$ akashica init --storage-type s3

S3 Bucket: my-company-akashica
S3 Prefix: repos/cloud-assets
Region [us-east-1]: us-west-2

✓ Created repository at s3://my-company-akashica/repos/cloud-assets
✓ Attached workspace at ~/projects/cloud-assets

# Files automatically uploaded to S3
$ akashica commit -m "Add assets"
✓ Uploaded 3 objects to S3
✓ Committed @1001 to main
```

## Implementation Plan

### Phase 1: Core Architecture (v0.10.0)

#### 1.1 Repository Detection

```swift
func detectRepository(at url: URL) async throws -> RepositoryDetectionResult {
    let fm = FileManager.default

    // Check for essential directories
    let branchesPath = url.appendingPathComponent("branches")
    let objectsPath = url.appendingPathComponent("objects")
    let changesetPath = url.appendingPathComponent("changeset")

    let hasBranches = fm.fileExists(atPath: branchesPath.path)
    let hasObjects = fm.fileExists(atPath: objectsPath.path)
    let hasChangeset = fm.fileExists(atPath: changesetPath.path)

    // Repository exists if it has the core directory structure
    if hasBranches || hasObjects || hasChangeset {
        // Validate it's a valid repository
        if hasBranches {
            // Check for at least one branch file
            let contents = try? fm.contentsOfDirectory(
                at: branchesPath,
                includingPropertiesForKeys: nil
            )
            let hasBranchFiles = contents?.contains(where: {
                $0.pathExtension == "json"
            }) ?? false

            if hasBranchFiles {
                return .found(version: try detectRepoVersion(at: url))
            }
        }

        // Partial/corrupted repository
        return .corrupted(
            hasBranches: hasBranches,
            hasObjects: hasObjects,
            hasChangeset: hasChangeset
        )
    }

    // Not a repository
    return .notFound
}

enum RepositoryDetectionResult {
    case found(version: String)
    case corrupted(hasBranches: Bool, hasObjects: Bool, hasChangeset: Bool)
    case notFound
}

func detectRepoVersion(at url: URL) throws -> String {
    // Check for version marker (future-proofing)
    let versionPath = url.appendingPathComponent(".akashica-version")
    if FileManager.default.fileExists(atPath: versionPath.path) {
        let data = try Data(contentsOf: versionPath)
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Legacy: no version file = v1.0
    return "1.0"
}
```

#### 1.2 Init Command (Create vs Attach)

```swift
struct Init: AsyncParsableCommand {
    @Option(help: "Repository storage path")
    var storagePath: String?

    @Option(help: "Storage type (local/s3)")
    var storageType: String?

    @Flag(help: "Create new repository (fail if exists)")
    var create: Bool = false

    @Flag(help: "Attach to existing repository (fail if not exists)")
    var attach: Bool = false

    func run() async throws {
        let storageURL = try resolveStoragePath()

        let detection = try await detectRepository(at: storageURL)

        switch detection {
        case .found(let version):
            // Repository exists
            if create {
                throw AkashicaError.repositoryExists(storageURL)
            }
            // Proceed with attach
            print("✓ Found existing repository (version \(version))")
            try await attachToRepository(at: storageURL, version: version)

        case .corrupted(let has):
            throw AkashicaError.corruptedRepository(
                path: storageURL,
                details: """
                Found incomplete repository structure:
                  branches/: \(has.hasBranches ? "✓" : "✗")
                  objects/:  \(has.hasObjects ? "✓" : "✗")
                  changeset/: \(has.hasChangeset ? "✓" : "✗")

                Repository may be corrupted or partially initialized.
                """
            )

        case .notFound:
            // No repository
            if attach {
                throw AkashicaError.repositoryNotFound(storageURL)
            }
            // Proceed with create
            print("No repository found. Creating new repository...")
            try await createRepository(at: storageURL)
        }
    }
}

enum InitMode {
    case create  // Initialize new repository
    case attach  // Attach workspace to existing repository
}
```

#### 1.3 Repository Creation

```swift
func createRepository(at url: URL) async throws {
    let fm = FileManager.default

    // Create directory structure
    try fm.createDirectory(
        at: url.appendingPathComponent("branches"),
        withIntermediateDirectories: true
    )
    try fm.createDirectory(
        at: url.appendingPathComponent("objects"),
        withIntermediateDirectories: true
    )
    try fm.createDirectory(
        at: url.appendingPathComponent("changeset"),
        withIntermediateDirectories: true
    )

    // Write version marker (for future migration detection)
    let versionPath = url.appendingPathComponent(".akashica-version")
    try "1.0".write(to: versionPath, atomically: true, encoding: .utf8)

    // Create initial main branch (empty)
    let storage = LocalStorageAdapter(rootPath: url)
    let initialCommit = CommitID.initial()

    try await storage.writeCommitMetadata(
        commit: initialCommit,
        metadata: CommitMetadata(
            id: initialCommit,
            parents: [],
            message: "Initial commit",
            author: "system",
            timestamp: Date.now,
            rootManifestHash: ContentHash.empty()
        )
    )

    try await storage.updateBranch(
        name: "main",
        expectedCurrent: nil,
        newCommit: initialCommit
    )
}
```

#### 1.4 Workspace Configuration

```swift
struct WorkspaceConfig: Codable {
    let version: String
    let repositoryId: String
    let storage: StorageConfig
    let workspace: WorkspaceState
    let view: ViewState?
    let cache: CacheConfig?

    struct StorageConfig: Codable {
        let type: String  // "local" or "s3"
        let path: String? // For local: "/Volumes/NAS/repos/my-project"
        let bucket: String?  // For S3
        let prefix: String?  // For S3
        let region: String?  // For S3
    }

    struct WorkspaceState: Codable {
        let id: String           // "@1045$ws_a3f2b8d9" - canonical format
        let branch: String       // "main"
        let baseCommit: String   // "@1045"
        let created: Date
        let lastSync: Date?
    }

    struct ViewState: Codable {
        let active: Bool
        let commit: String?      // "@1032" - if in view mode
        let startedAt: Date?
    }

    struct CacheConfig: Codable {
        let enabled: Bool
        let maxSize: String      // "10GB"
        let currentSize: String? // "2.3GB"
    }
}

func createWorkspace(
    at workingDir: URL,
    storage: StorageLocation,
    branch: String,
    baseCommit: CommitID
) async throws {
    // Generate workspace suffix
    let suffix = String(UUID().uuidString.prefix(8))

    // Build canonical workspace ID: @1045$ws_a3f2b8d9
    let workspaceID = WorkspaceID(
        baseCommit: baseCommit,
        suffix: suffix
    )

    let config = WorkspaceConfig(
        version: "1.0",
        repositoryId: storage.repositoryName,
        storage: storage.config,
        workspace: WorkspaceConfig.WorkspaceState(
            id: workspaceID.fullReference,  // "@1045$ws_a3f2b8d9"
            branch: branch,
            baseCommit: baseCommit.value,   // "@1045"
            created: Date.now,
            lastSync: nil
        ),
        view: WorkspaceConfig.ViewState(
            active: false,
            commit: nil,
            startedAt: nil
        ),
        cache: nil
    )

    try saveWorkspaceConfig(config, at: workingDir)
}

func reopenWorkspace(at workingDir: URL) async throws -> (WorkspaceID, WorkspaceMode) {
    let config = try loadWorkspaceConfig(at: workingDir)

    // Parse canonical workspace ID: @1045$ws_a3f2b8d9
    let workspaceID = WorkspaceID(fullReference: config.workspace.id)

    // Check if view mode was active
    if config.view?.active == true,
       let viewCommitStr = config.view?.commit {
        let viewCommit = CommitID(value: viewCommitStr)
        return (workspaceID, .viewing(commit: viewCommit))
    }

    // Normal workspace mode
    return (workspaceID, .working(branch: config.workspace.branch))
}

enum WorkspaceMode {
    case working(branch: String)
    case viewing(commit: CommitID)
}
```

#### 1.5 StorageAdapter Protocol Updates

```swift
protocol StorageAdapter {
    // Repository location
    var repositoryRoot: StorageLocation { get }
    var workspaceRoot: URL? { get }  // Optional, may be remote-only

    // NEW: Repository-wide locking
    func acquireRepositoryLock(
        operation: String,
        timeout: Duration
    ) async throws -> RepositoryLock

    func releaseRepositoryLock(_ lock: RepositoryLock) async throws

    // Existing operations...
}

struct StorageLocation {
    enum Kind {
        case local(path: URL)
        case s3(bucket: String, prefix: String)
    }

    let kind: Kind
    let repositoryName: String

    var config: WorkspaceConfig.StorageConfig {
        switch kind {
        case .local(let path):
            return WorkspaceConfig.StorageConfig(
                type: "local",
                path: path.path,
                bucket: nil,
                prefix: nil,
                region: nil
            )
        case .s3(let bucket, let prefix):
            return WorkspaceConfig.StorageConfig(
                type: "s3",
                path: nil,
                bucket: bucket,
                prefix: prefix,
                region: "us-east-1"  // TODO: Configurable
            )
        }
    }
}

struct RepositoryLock {
    let lockId: String
    let acquiredAt: Date
    let operation: String
}

// Extension for automatic lock management
extension StorageAdapter {
    func withRepositoryLock<T>(
        operation: String,
        timeout: Duration = .seconds(30),
        _ body: () async throws -> T
    ) async throws -> T {
        let lock = try await acquireRepositoryLock(
            operation: operation,
            timeout: timeout
        )
        defer {
            Task {
                try? await releaseRepositoryLock(lock)
            }
        }
        return try await body()
    }
}
```

#### 1.6 Concurrent Writer Protection

**Local Filesystem Locking**:
```swift
extension LocalStorageAdapter {
    func acquireRepositoryLock(
        operation: String,
        timeout: Duration
    ) async throws -> RepositoryLock {
        let lockPath = rootPath.appendingPathComponent(".lock")
        let lockId = UUID().uuidString

        let deadline = Date.now.addingTimeInterval(timeout.components.seconds)

        while Date.now < deadline {
            // Try to create lock file atomically
            let lockData = LockMetadata(
                lockId: lockId,
                operation: operation,
                pid: ProcessInfo.processInfo.processIdentifier,
                hostname: ProcessInfo.processInfo.hostName ?? "unknown",
                acquiredAt: Date.now
            )

            let data = try JSONEncoder().encode(lockData)

            do {
                // O_CREAT | O_EXCL = atomic create-if-not-exists
                try data.write(to: lockPath, options: .withoutOverwriting)

                return RepositoryLock(
                    lockId: lockId,
                    acquiredAt: Date.now,
                    operation: operation
                )
            } catch {
                // Lock exists, check if stale
                if try isLockStale(at: lockPath) {
                    try? FileManager.default.removeItem(at: lockPath)
                    continue
                }

                // Wait and retry
                try await Task.sleep(for: .milliseconds(100))
            }
        }

        throw AkashicaError.lockTimeout(operation: operation)
    }

    func isLockStale(at path: URL) throws -> Bool {
        let data = try Data(contentsOf: path)
        let metadata = try JSONDecoder().decode(LockMetadata.self, from: data)

        // Lock is stale if:
        // 1. Older than 5 minutes
        // 2. Process no longer exists (if local)
        let isOld = Date.now.timeIntervalSince(metadata.acquiredAt) > 300

        #if os(macOS) || os(Linux)
        let processExists = kill(metadata.pid, 0) == 0
        return isOld || !processExists
        #else
        return isOld
        #endif
    }
}

struct LockMetadata: Codable {
    let lockId: String
    let operation: String
    let pid: Int32
    let hostname: String
    let acquiredAt: Date
}
```

**S3 Locking** (using conditional PUT):
```swift
extension S3StorageAdapter {
    func acquireRepositoryLock(
        operation: String,
        timeout: Duration
    ) async throws -> RepositoryLock {
        let lockKey = "\(prefix)/locks/repository.lock"
        let lockId = UUID().uuidString

        let lockData = LockMetadata(
            lockId: lockId,
            operation: operation,
            pid: 0,  // N/A for S3
            hostname: ProcessInfo.processInfo.hostName ?? "unknown",
            acquiredAt: Date.now
        )

        let data = try JSONEncoder().encode(lockData)

        // Use S3 conditional PUT: only succeed if lock doesn't exist
        let request = PutObjectRequest(
            bucket: bucket,
            key: lockKey,
            body: data,
            ifNoneMatch: "*"  // Only create if doesn't exist
        )

        let deadline = Date.now.addingTimeInterval(timeout.components.seconds)

        while Date.now < deadline {
            do {
                try await s3Client.putObject(request)
                return RepositoryLock(
                    lockId: lockId,
                    acquiredAt: Date.now,
                    operation: operation
                )
            } catch let error as S3Error where error.code == "PreconditionFailed" {
                // Lock exists, check if stale
                if try await isS3LockStale(key: lockKey) {
                    try? await s3Client.deleteObject(bucket: bucket, key: lockKey)
                    continue
                }

                try await Task.sleep(for: .milliseconds(100))
            }
        }

        throw AkashicaError.lockTimeout(operation: operation)
    }
}
```

**Usage in Repository Operations**:
```swift
public func commit(message: String) async throws -> CommitID {
    // Acquire lock before updating branch pointer
    try await storage.withRepositoryLock(operation: "commit") {
        let workspaceID = try currentWorkspaceID()
        let metadata = try await storage.readWorkspaceMetadata(workspace: workspaceID)

        // ... build manifests, write objects ...

        let commitID = CommitID.next()
        try await storage.writeCommitMetadata(commit: commitID, metadata: commitMeta)

        // CRITICAL: Update branch pointer atomically under lock
        try await storage.updateBranch(
            name: metadata.branch,
            expectedCurrent: metadata.baseCommit,
            newCommit: commitID
        )

        return commitID
    }
}
```

### Phase 2: Workspace Management (v0.11.0)

- Multiple workspace support
- Workspace listing/cleanup commands
- Workspace metadata sync
- Branch switching across workspaces

### Phase 3: Cache Layer (v0.12.0)

- Object cache implementation
- LRU eviction strategy
- Cache size management
- Prefetch optimization for S3

## Migration Path

### For Existing Repositories (v0.9.0 → v0.10.0)

```bash
# Old style (storage in current dir)
$ cd ~/old-repo
$ ls -la
.akashica/  objects/  branches/  changeset/

# Migration command
$ akashica migrate --storage-path /Volumes/NAS/repos/old-repo

Moving repository storage...
✓ Moved objects/ to /Volumes/NAS/repos/old-repo/objects/
✓ Moved branches/ to /Volumes/NAS/repos/old-repo/branches/
✓ Moved changeset/ to /Volumes/NAS/repos/old-repo/changeset/
✓ Created .akashica-version
✓ Updated .akashica/config
✓ Workspace ready at ~/old-repo

$ ls -la
.akashica/  # Only workspace config remains
```

**Backward Compatibility**:
- Existing repos without `.akashica-version` default to version "1.0"
- Detection based on actual directory structure (`branches/*.json`)
- No breaking changes to data format

## Benefits

### Scalability
- Multi-TB repositories on NAS without filling working directories
- S3 storage for cloud-native workflows
- Working directories stay small and fast

### Collaboration
- Multiple team members with independent workspaces
- Shared repository storage (like Git bare repos)
- No repository duplication

### Flexibility
- Working directory can be temporary/ephemeral
- Repository storage on reliable/backed-up volumes
- Easy to clean up/recreate workspaces

### Performance
- Cache layer reduces network/disk I/O (Phase 3)
- Parallel operations across workspaces
- Repository-level locking prevents corruption

## Open Questions

1. **Default storage location**: Should we provide smart defaults (e.g., `~/Library/Akashica/repos/`) for users who don't specify?
2. **Workspace cleanup**: Automatic detection/cleanup of abandoned workspaces?
3. **Cache eviction strategy**: LRU vs LFU vs time-based?
4. **S3 credentials**: How to handle AWS credential management in config?

## References

- Current design: `/Users/kyoshikawa/Projects/akashica/docs/design.md`
- Workspace design: `/Users/kyoshikawa/Projects/akashica/docs/WORKSPACE_DESIGN_SUMMARY.md`
- Virtual filesystem: `/Users/kyoshikawa/Projects/akashica/docs/VIRTUAL_FILESYSTEM.md`
