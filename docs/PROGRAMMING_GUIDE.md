# Akashica Programming Guide

A comprehensive guide for Swift developers integrating Akashica into macOS, iOS, or server-side Swift applications.

## Table of Contents

1. [Introduction](#introduction)
2. [What is Akashica?](#what-is-akashica)
3. [Getting Started](#getting-started)
4. [Storage Configuration](#storage-configuration)
5. [Understanding the Two-Tier Model](#understanding-the-two-tier-model)
6. [Sessions and Repository Pattern](#sessions-and-repository-pattern)
7. [Basic Operations](#basic-operations)
8. [Workspace Workflow](#workspace-workflow)
9. [Branch Management](#branch-management)
10. [Content Scrubbing](#content-scrubbing)
11. [Error Handling](#error-handling)
12. [Credential Management](#credential-management)
13. [Performance Considerations](#performance-considerations)
14. [Testing](#testing)
15. [API Reference](#api-reference)

---

## Introduction

This guide is for **professional Swift developers** building macOS, iOS, or server-side applications that need robust content versioning and management. You should be familiar with:

- Swift 5.9+ and Swift Concurrency (`async`/`await`, `actor`)
- AWS S3 (for cloud storage scenarios)
- Content-addressed storage concepts (helpful but not required)

**You do NOT need to know:**
- Akashica's internals or implementation details
- Git or other version control systems (though analogies will be made)

**What you'll learn:**
- How to integrate Akashica into your Swift app
- How to manage versioned content with workspaces and commits
- How to handle AWS credentials securely
- How to perform all content operations (read, write, delete, move, scrub)
- Best practices for production deployments

---

## What is Akashica?

Akashica is a **content-addressed version control library** for Swift applications. Unlike traditional file storage, Akashica:

1. **Versions everything** - Every change creates an immutable snapshot
2. **Deduplicates automatically** - Identical content stored only once (by SHA-256 hash)
3. **Enables concurrent editing** - Multiple users work in isolated workspaces
4. **Supports multiple backends** - Local filesystem or AWS S3, same API
5. **Provides type-safe API** - Swift actors ensure thread-safe concurrent access

### Why Akashica?

**Problem:** Your app manages user-generated content (documents, configurations, media) and needs:
- Complete version history with rollback capability
- Concurrent multi-user editing without conflicts
- Storage efficiency (deduplication)
- Audit trail (who changed what, when, why)

**Solution:** Akashica provides a Git-like versioning system as a Swift library, purpose-built for content management applications.

### Use Cases

1. **Document Management App** (macOS/iOS)
   - Users edit documents in isolated workspaces
   - Preview changes before publishing
   - Rollback to any previous version

2. **Configuration Management** (Server-side Swift)
   - Track configuration changes across environments
   - Branch-based workflow (dev → staging → production)
   - Audit compliance with full history

3. **CMS Backend** (Vapor/Server)
   - Multiple editors work on content simultaneously
   - Content approval workflow via workspaces
   - S3 storage for cloud-native architecture

4. **Collaborative Creative Tools** (macOS)
   - Artists work on isolated copies
   - Merge-free collaboration (each has own workspace)
   - Version history for every creative asset

---

## Getting Started

### Installation

Add Akashica to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/codelynx/akashica.git", from: "1.0.0")
]
```

**For local storage only:**
```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Akashica", package: "akashica"),
            .product(name: "AkashicaStorage", package: "akashica")
        ]
    )
]
```

**For S3 storage:**
```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "Akashica", package: "akashica"),
            .product(name: "AkashicaS3Storage", package: "akashica")
        ]
    )
]
```

**Note:** `AkashicaS3Storage` includes AWS SDK dependencies. Use `AkashicaStorage` if you only need local filesystem support.

### Quick Example

```swift
import Akashica
import AkashicaStorage

// 1. Initialize repository with local storage
let storage = LocalStorageAdapter(
    rootPath: URL(fileURLWithPath: "/path/to/repo/.akashica")
)
let repo = AkashicaRepository(storage: storage)

// 2. Create workspace from initial commit
let workspace = try await repo.createWorkspace(from: CommitID(value: "@0"))
let session = repo.session(workspace: workspace)

// 3. Add content
let data = "Hello, World!".data(using: .utf8)!
try await session.writeFile(data, to: "hello.txt")

// 4. Check status
let status = try await session.status()
print("Added files: \(status.added)")  // ["hello.txt"]

// 5. Publish to branch
let commit = try await repo.publishWorkspace(
    workspace,
    toBranch: "main",
    message: "Initial content",
    author: "alice@example.com"
)

print("Created commit: \(commit.value)")  // "@1234"
```

That's it! You've created a versioned content repository with full history tracking.

---

## Storage Configuration

Akashica supports two storage backends: **local filesystem** and **AWS S3**. Choose based on your deployment model.

### Local Filesystem Storage

**Best for:**
- macOS/iOS apps with on-device storage
- Development and testing
- Single-user scenarios
- Air-gapped or offline-first applications

**Setup:**

```swift
import Akashica
import AkashicaStorage

// Initialize storage adapter
let documentsPath = FileManager.default.urls(
    for: .documentDirectory,
    in: .userDomainMask
).first!

let storagePath = documentsPath
    .appendingPathComponent("MyApp")
    .appendingPathComponent(".akashica")

let storage = LocalStorageAdapter(rootPath: storagePath)
let repo = AkashicaRepository(storage: storage)
```

**Storage layout:**
```
/Users/alice/Documents/MyApp/
└── .akashica/
    ├── objects/            # Content-addressed files (SHA-256)
    ├── manifests/          # Directory structures
    ├── changeset/
    │   ├── @0/             # Initial commit
    │   ├── @1234/          # Subsequent commits
    │   └── @1234$a1b3/     # Active workspaces
    └── branches/
        └── main.json       # Branch pointer
```

**Considerations:**
- All data stored locally (no network required)
- Storage size limited by device capacity
- Fast access (no network latency)
- No built-in backup/sync (use iCloud, Dropbox, etc.)

### AWS S3 Storage

**Best for:**
- Server-side Swift applications (Vapor, Hummingbird)
- Multi-user cloud applications
- Large-scale content (terabytes+)
- Distributed teams
- Cloud-native architectures

**Setup:**

```swift
import Akashica
import AkashicaS3Storage

// Initialize S3 storage adapter
let storage = try await S3StorageAdapter(
    region: "us-east-1",
    bucket: "my-app-content"
)

let repo = AkashicaRepository(storage: storage)
```

**S3 storage layout:**
```
s3://my-app-content/
├── objects/<hash>          # Content-addressed files
├── manifests/<hash>        # Directory structures
├── commits/@1234/
│   ├── root-manifest
│   └── metadata.json
├── branches/main           # Branch pointer
└── workspaces/@1234$a1b3/
    ├── metadata.json
    ├── files/
    └── cow/
```

**Multi-tenant setup (optional):**

If you're building a SaaS app with multiple customers sharing one S3 bucket:

```swift
// Each tenant gets isolated prefix
let tenantID = "customer-abc123"

let storage = try await S3StorageAdapter(
    region: "us-east-1",
    bucket: "shared-app-content",
    keyPrefix: tenantID  // All keys: "customer-abc123/objects/..."
)
```

**Layout with prefixes:**
```
s3://shared-app-content/
├── customer-abc123/
│   ├── objects/
│   ├── commits/
│   └── branches/
└── customer-xyz789/
    ├── objects/
    ├── commits/
    └── branches/
```

**Considerations:**
- Requires AWS credentials (see [Credential Management](#credential-management))
- Network latency affects performance
- Virtually unlimited storage capacity
- Built-in durability (11 9's with S3)
- Costs scale with storage + API calls

---

## Understanding the Two-Tier Model

Akashica uses a **dual-tier architecture** inspired by Git but optimized for content management applications.

### Tier 1: Commits (Immutable)

**Commits** are immutable snapshots of your content at a specific point in time.

```swift
// Commit ID format: @<number>
let commitID = CommitID(value: "@1234")
```

**Properties:**
- **Read-only** - Once created, never changes
- **Identified by number** - `@0`, `@1234`, `@5678`
- **Contains metadata** - Author, message, timestamp, parent commit
- **Content-addressed** - Files stored by SHA-256 hash (automatic deduplication)

**Creating commits:**
- Initial commit `@0` created automatically
- New commits created by publishing workspaces
- Each commit knows its parent (forms a chain)

```swift
// Read commit metadata
let metadata = try await repo.commitMetadata(commitID)
print("Author: \(metadata.author)")
print("Message: \(metadata.message)")
print("Timestamp: \(metadata.timestamp)")
print("Parent: \(metadata.parent?.value ?? "none")")

// Read file from commit (read-only)
let session = repo.session(commit: commitID)
let data = try await session.readFile(at: "README.md")
```

### Tier 2: Workspaces (Mutable)

**Workspaces** are ephemeral editing sessions based on a parent commit.

```swift
// Workspace ID format: @<base>$<suffix>
// Example: @1234$a1b3
let workspaceID = try await repo.createWorkspace(from: commitID)
```

**Properties:**
- **Read-write** - Can add, modify, delete files
- **Ephemeral** - Deleted after publishing or explicit deletion
- **Isolated** - Multiple workspaces never interfere with each other
- **Based on commit** - Starts as a copy of parent commit
- **Copy-on-write (COW)** - Efficient storage via references

**Lifecycle:**
1. **Create** - From a commit or branch
2. **Edit** - Make changes (add/modify/delete files)
3. **Status** - Check what changed
4. **Publish** - Create new commit from workspace
5. **Delete** - Clean up (automatic after publish, or manual)

```swift
// Create workspace
let workspace = try await repo.createWorkspace(from: commitID)
let session = repo.session(workspace: workspace)

// Make changes
try await session.writeFile(newData, to: "document.txt")
try await session.deleteFile(at: "obsolete.txt")

// Check what changed
let status = try await session.status()
print("Modified: \(status.modified)")
print("Deleted: \(status.deleted)")

// Publish to create new commit
let newCommit = try await repo.publishWorkspace(
    workspace,
    toBranch: "main",
    message: "Updated document",
    author: "alice@example.com"
)

// Workspace automatically deleted after publish
```

### Why Two Tiers?

**Problem:** Git's model (everything is a commit) doesn't fit content apps well:
- Making a commit for every keystroke is impractical
- Uncommitted changes are fragile (no version history)
- Collaboration requires merge conflict resolution

**Solution:** Separate "work in progress" (workspace) from "published version" (commit):

| Aspect | Workspace | Commit |
|--------|-----------|--------|
| Mutability | Read-write | Read-only |
| Durability | Ephemeral | Permanent |
| Isolation | Per-user/session | Shared |
| Performance | Fast (local changes) | Slower (full snapshot) |
| Use case | Editing | Publishing |

### Branching Model

**Branches** are named pointers to commits, just like Git:

```swift
// Branch "main" points to commit @1234
let currentCommit = try await repo.currentCommit(branch: "main")
// Returns: CommitID(value: "@1234")

// List all branches
let branches = try await repo.branches()
// Returns: ["main", "develop", "feature-xyz"]
```

**Creating workspaces from branches:**

```swift
// Create workspace from latest commit on branch
let workspace = try await repo.createWorkspace(fromBranch: "main")

// Edit and publish back to same branch
let newCommit = try await repo.publishWorkspace(
    workspace,
    toBranch: "main",  // Updates "main" to point at new commit
    message: "Update",
    author: "alice"
)
```

**Branch workflow:**

```
main:     @0 ← @1234 ← @5678          (production content)
            ↖︎
develop:      @2345 ← @3456            (staging content)
```

1. Create workspace from `main` → edit → publish to `develop`
2. Review changes in `develop` branch
3. If approved, create workspace from `develop` → publish to `main`

---

## Sessions and Repository Pattern

Akashica uses a **session-based API** where all content operations go through session objects.

### Repository Actor

`AkashicaRepository` is the entry point - a stateless factory for creating sessions:

```swift
actor AkashicaRepository {
    init(storage: StorageAdapter)

    // Session factory
    func session(commit: CommitID) -> AkashicaSession
    func session(workspace: WorkspaceID) -> AkashicaSession
    func session(branch: String) async throws -> AkashicaSession

    // Workspace lifecycle
    func createWorkspace(from: CommitID) async throws -> WorkspaceID
    func createWorkspace(fromBranch: String) async throws -> WorkspaceID
    func publishWorkspace(_:toBranch:message:author:) async throws -> CommitID
    func deleteWorkspace(_ workspace: WorkspaceID) async throws

    // Branch operations
    func branches() async throws -> [String]
    func currentCommit(branch: String) async throws -> CommitID

    // Commit metadata
    func commitMetadata(_ commit: CommitID) async throws -> CommitMetadata
    func commitHistory(branch: String, limit: Int) async throws -> [(CommitID, CommitMetadata)]

    // Content scrubbing (advanced)
    func scrubContent(hash: ContentHash, reason: String, deletedBy: String) async throws
}
```

**Design principle:** Repository has no state. All operations are async and actor-isolated.

### Session Actor

`AkashicaSession` represents a view into a specific commit or workspace:

```swift
actor AkashicaSession {
    let changeset: ChangesetRef  // .commit(@1234) or .workspace(@1234$a1b3)
    var isReadOnly: Bool          // true for commits, false for workspaces

    // Reading (works for commits and workspaces)
    func readFile(at: RepositoryPath) async throws -> Data
    func listDirectory(at: RepositoryPath) async throws -> [DirectoryEntry]
    func fileExists(at: RepositoryPath) async throws -> Bool

    // Writing (workspaces only)
    func writeFile(_ data: Data, to: RepositoryPath) async throws
    func deleteFile(at: RepositoryPath) async throws
    func moveFile(from: RepositoryPath, to: RepositoryPath) async throws

    // Status & diff
    func status() async throws -> WorkspaceStatus
    func diff(against: CommitID) async throws -> [FileChange]
}
```

**Design principle:** Each session is tied to one changeset. Multiple sessions never interfere.

### Session Independence

Multiple sessions can coexist without conflicts:

```swift
let repo = AkashicaRepository(storage: storage)

// User A edits workspace @1234$aaaa
let sessionA = repo.session(workspace: workspaceA)
try await sessionA.writeFile(dataA, to: "file.txt")

// User B edits workspace @1234$bbbb (different workspace)
let sessionB = repo.session(workspace: workspaceB)
try await sessionB.writeFile(dataB, to: "file.txt")

// User C reads commit @1234 (immutable)
let sessionC = repo.session(commit: commitID)
let original = try await sessionC.readFile(at: "file.txt")

// All three operations are independent - no conflicts!
```

This is possible because:
1. Each workspace stores changes separately
2. Sessions don't share mutable state
3. Actor isolation prevents race conditions

---

## Basic Operations

### Reading Files

```swift
let session = repo.session(commit: commitID)

// Read entire file
let data = try await session.readFile(at: "documents/report.pdf")

// Check if file exists
let exists = try await session.fileExists(at: "config.json")

// Handle missing files
do {
    let data = try await session.readFile(at: "missing.txt")
} catch AkashicaError.fileNotFound(let path) {
    print("File not found: \(path)")
}
```

**Path format:**
```swift
// String literal (ExpressibleByStringLiteral)
let path: RepositoryPath = "asia/japan/tokyo.txt"

// Explicit construction
let path = RepositoryPath(string: "asia/japan/tokyo.txt")

// Components
path.components  // ["asia", "japan", "tokyo.txt"]
path.name        // "tokyo.txt"
path.parent      // RepositoryPath("asia/japan")
```

### Listing Directories

```swift
let session = repo.session(commit: commitID)

// List directory
let entries = try await session.listDirectory(at: "documents")

for entry in entries {
    switch entry.type {
    case .file:
        print("File: \(entry.name) (\(entry.size) bytes)")
    case .directory:
        print("Dir:  \(entry.name)/")
    }
}
```

**DirectoryEntry:**
```swift
struct DirectoryEntry {
    let name: String
    let type: EntryType  // .file or .directory
    let hash: ContentHash?  // nil for directories
    let size: Int64?        // nil for directories
}
```

### Writing Files

**Only works on workspace sessions:**

```swift
let workspace = try await repo.createWorkspace(fromBranch: "main")
let session = repo.session(workspace: workspace)

// Write file
let content = "Updated content".data(using: .utf8)!
try await session.writeFile(content, to: "document.txt")

// Write nested file (creates parent directories automatically)
try await session.writeFile(data, to: "reports/2025/january/summary.pdf")

// Attempting to write on commit session throws error
let readOnlySession = repo.session(commit: commitID)
try await readOnlySession.writeFile(data, to: "file.txt")
// Throws: AkashicaError.sessionReadOnly
```

### Deleting Files

```swift
let session = repo.session(workspace: workspace)

// Delete file
try await session.deleteFile(at: "obsolete.txt")

// Delete nested file
try await session.deleteFile(at: "old/deprecated/ancient.txt")

// Deleting non-existent file throws error
try await session.deleteFile(at: "nonexistent.txt")
// Throws: AkashicaError.fileNotFound
```

### Moving Files

```swift
let session = repo.session(workspace: workspace)

// Rename file
try await session.moveFile(
    from: "old-name.txt",
    to: "new-name.txt"
)

// Move to different directory
try await session.moveFile(
    from: "draft.txt",
    to: "published/final.txt"
)

// Move creates parent directories automatically
try await session.moveFile(
    from: "doc.pdf",
    to: "archive/2024/december/doc.pdf"
)
```

**Note:** Move is implemented using **copy-on-write (COW) references** for efficiency:
- Original file content stays in storage (by hash)
- New path gets a reference to the same content
- No data duplication

---

## Workspace Workflow

The typical workflow for editing content:

### 1. Create Workspace

```swift
// From specific commit
let workspace = try await repo.createWorkspace(from: commitID)

// From latest commit on branch
let workspace = try await repo.createWorkspace(fromBranch: "main")
```

**Returns:** `WorkspaceID` (e.g., `@1234$a1b3`)

### 2. Get Session

```swift
let session = repo.session(workspace: workspace)
```

### 3. Make Changes

```swift
// Add new file
try await session.writeFile(newData, to: "article.md")

// Modify existing file
let existing = try await session.readFile(at: "config.json")
let updated = modifyJSON(existing)
try await session.writeFile(updated, to: "config.json")

// Delete file
try await session.deleteFile(at: "draft.txt")

// Rename file
try await session.moveFile(from: "temp.txt", to: "final.txt")
```

### 4. Check Status

```swift
let status = try await session.status()

print("Added files:")
for path in status.added {
    print("  + \(path)")
}

print("Modified files:")
for path in status.modified {
    print("  M \(path)")
}

print("Deleted files:")
for path in status.deleted {
    print("  D \(path)")
}
```

**WorkspaceStatus:**
```swift
struct WorkspaceStatus {
    let added: [RepositoryPath]      // New files
    let modified: [RepositoryPath]   // Changed files
    let deleted: [RepositoryPath]    // Removed files
}
```

### 5. Publish or Discard

**Option A: Publish (create new commit)**

```swift
let newCommit = try await repo.publishWorkspace(
    workspace,
    toBranch: "main",
    message: "Add new article and update config",
    author: "alice@example.com"
)

print("Published as: \(newCommit.value)")
// Workspace automatically deleted after publish
```

**Option B: Discard changes**

```swift
// Manually delete workspace without creating commit
try await repo.deleteWorkspace(workspace)
```

### Complete Example

```swift
import Akashica
import AkashicaStorage

func updateDocument(repo: AkashicaRepository) async throws {
    // 1. Create workspace from main branch
    let workspace = try await repo.createWorkspace(fromBranch: "main")
    let session = repo.session(workspace: workspace)

    // 2. Make edits
    let newContent = """
    # Updated Document

    This content was updated on \(Date()).
    """.data(using: .utf8)!

    try await session.writeFile(newContent, to: "README.md")

    // 3. Check what changed
    let status = try await session.status()
    guard !status.modified.isEmpty else {
        print("No changes to publish")
        try await repo.deleteWorkspace(workspace)
        return
    }

    // 4. Publish changes
    let commit = try await repo.publishWorkspace(
        workspace,
        toBranch: "main",
        message: "Update README with timestamp",
        author: "bot@example.com"
    )

    print("Published commit: \(commit.value)")
}
```

---

## Branch Management

### Listing Branches

```swift
let branches = try await repo.branches()
// Returns: ["main", "develop", "feature-123"]

for branch in branches {
    let commit = try await repo.currentCommit(branch: branch)
    let metadata = try await repo.commitMetadata(commit)
    print("\(branch): \(commit.value) - \(metadata.message)")
}
```

### Getting Branch Commit

```swift
let mainCommit = try await repo.currentCommit(branch: "main")
// Returns: CommitID(value: "@1234")
```

### Creating Branch (via Publish)

Branches are created implicitly when you publish to a non-existent branch name:

```swift
// Create workspace from main
let workspace = try await repo.createWorkspace(fromBranch: "main")
let session = repo.session(workspace: workspace)

// Make changes
try await session.writeFile(experimentalData, to: "experiment.txt")

// Publish to new branch "feature-xyz"
let commit = try await repo.publishWorkspace(
    workspace,
    toBranch: "feature-xyz",  // New branch created automatically
    message: "Experimental feature",
    author: "bob@example.com"
)

// Branch "feature-xyz" now exists and points to new commit
```

### Branch Workflow Example

**Scenario:** Development → Staging → Production pipeline

```swift
// 1. Create feature from develop
let workspace = try await repo.createWorkspace(fromBranch: "develop")
let session = repo.session(workspace: workspace)

// 2. Implement feature
try await session.writeFile(featureCode, to: "features/new-feature.swift")

// 3. Publish to develop branch
let devCommit = try await repo.publishWorkspace(
    workspace,
    toBranch: "develop",
    message: "Add new feature",
    author: "dev@example.com"
)

// 4. After testing, promote to staging
let stagingWorkspace = try await repo.createWorkspace(fromBranch: "develop")
let stagingCommit = try await repo.publishWorkspace(
    stagingWorkspace,
    toBranch: "staging",
    message: "Promote to staging",
    author: "ci@example.com"
)

// 5. After approval, promote to production
let prodWorkspace = try await repo.createWorkspace(fromBranch: "staging")
let prodCommit = try await repo.publishWorkspace(
    prodWorkspace,
    toBranch: "main",  // Production branch
    message: "Release to production",
    author: "ci@example.com"
)
```

### Viewing Commit History

```swift
// Get last 10 commits on branch
let history = try await repo.commitHistory(branch: "main", limit: 10)

for (commit, metadata) in history {
    let date = metadata.timestamp.formatted()
    print("[\(commit.value)] \(metadata.author) - \(metadata.message)")
    print("  Date: \(date)")
    if let parent = metadata.parent {
        print("  Parent: \(parent.value)")
    }
    print()
}
```

**Output:**
```
[@1234] alice@example.com - Update README
  Date: 2025-10-07 14:30:00
  Parent: @1233

[@1233] bob@example.com - Add new feature
  Date: 2025-10-07 10:15:00
  Parent: @1232

[@1232] charlie@example.com - Fix bug
  Date: 2025-10-06 16:45:00
  Parent: @0
```

---

## Content Scrubbing

**Content scrubbing** permanently removes sensitive content (API keys, PII, secrets) from the repository while preserving commit integrity.

### Why Scrubbing?

**Problem:** You accidentally committed sensitive data:
```swift
// Oops! Committed AWS credentials
try await session.writeFile(
    "AWS_KEY=AKIAIOSFODNN7EXAMPLE".data(using: .utf8)!,
    to: "config/secrets.env"
)
let badCommit = try await repo.publishWorkspace(...)
```

**Traditional solutions:**
- Git: Rewrite history (`git-filter-repo`, `BFG`) → breaks existing commits, requires force-push
- Delete repository and start over → loses all history

**Akashica solution:** **Tombstones**
- Mark content as deleted (create `.tomb` file)
- Delete actual data
- Preserve commit structure (hashes unchanged)
- Maintain audit trail (who deleted, when, why)

### Scrubbing by Hash

```swift
// Find the hash of sensitive content
let session = repo.session(commit: badCommit)
let entries = try await session.listDirectory(at: "config")

// Get hash from directory entry
if let secretsEntry = entries.first(where: { $0.name == "secrets.env" }) {
    let sensitiveHash = secretsEntry.hash!

    // Permanently remove this content
    try await repo.scrubContent(
        hash: sensitiveHash,
        reason: "Accidentally committed AWS credentials",
        deletedBy: "security@example.com"
    )
}
```

### Scrubbing by Path

Convenience method that walks manifests to find the hash:

```swift
try await repo.scrubContent(
    at: RepositoryPath(string: "config/secrets.env"),
    in: badCommit,
    reason: "GDPR data removal request - user deletion",
    deletedBy: "compliance@example.com"
)
```

### What Happens During Scrubbing

1. **Locate content** - Find object by hash
2. **Create tombstone** - Write `.tomb` file with metadata
3. **Delete object** - Remove actual data file
4. **Preserve commits** - Commit structure unchanged

**Tombstone format:**
```json
{
  "deletedHash": "sha256:a3f2b1c4d5e6...",
  "reason": "Accidentally committed AWS credentials",
  "timestamp": "2025-10-07T14:30:00Z",
  "deletedBy": "security@example.com",
  "originalSize": 1024
}
```

### Audit Trail

List all scrubbed content for compliance reporting:

```swift
let scrubbed = try await repo.listScrubbedContent()

print("Scrubbed Content Audit Report")
print("=" * 50)

for (hash, tombstone) in scrubbed {
    print("Hash: \(hash.value)")
    print("Deleted by: \(tombstone.deletedBy)")
    print("Timestamp: \(tombstone.timestamp)")
    print("Reason: \(tombstone.reason)")
    print("Original size: \(tombstone.originalSize) bytes")
    print()
}
```

### Reading Scrubbed Content

Attempting to read scrubbed content throws an error:

```swift
do {
    let data = try await session.readFile(at: "config/secrets.env")
} catch AkashicaError.objectDeleted(let hash, let tombstone) {
    print("Content was deleted: \(tombstone.reason)")
    print("Deleted on: \(tombstone.timestamp)")
    print("Contact: \(tombstone.deletedBy)")
}
```

### Scrubbing Best Practices

1. **Audit before scrubbing** - Verify you're deleting the right content
2. **Document reason** - Use descriptive reasons for audit trail
3. **Check deduplication** - Same content may appear in multiple files
4. **Backup first** - Scrubbing is irreversible
5. **Notify team** - Scrubbed content affects all users

**Example: Responsible scrubbing**

```swift
func scrubSensitiveData(
    repo: AkashicaRepository,
    path: RepositoryPath,
    commit: CommitID
) async throws {
    // 1. Verify content exists
    let session = repo.session(commit: commit)
    guard try await session.fileExists(at: path) else {
        print("File not found: \(path)")
        return
    }

    // 2. Log action for audit
    let user = getCurrentUser()
    let timestamp = Date()
    print("[\(timestamp)] \(user) scrubbing: \(path) in \(commit.value)")

    // 3. Perform scrubbing
    try await repo.scrubContent(
        at: path,
        in: commit,
        reason: "Security incident #12345 - exposed API key",
        deletedBy: user
    )

    // 4. Verify scrubbing
    do {
        _ = try await session.readFile(at: path)
        throw ScrubbingError.verificationFailed
    } catch AkashicaError.objectDeleted {
        print("✓ Scrubbing verified")
    }

    // 5. Notify team
    await notifyTeam(
        "Content scrubbed: \(path) - Reason: Security incident #12345"
    )
}
```

---

## Error Handling

Akashica uses Swift's typed error system. All errors conform to `AkashicaError`:

```swift
enum AkashicaError: Error {
    case sessionReadOnly
    case workspaceNotFound(WorkspaceID)
    case commitNotFound(CommitID)
    case fileNotFound(RepositoryPath)
    case branchNotFound(String)
    case invalidManifest(String)
    case objectDeleted(hash: ContentHash, tombstone: Tombstone)
    case storageError(Error)
}
```

### Handling Common Errors

**File not found:**
```swift
do {
    let data = try await session.readFile(at: "missing.txt")
} catch AkashicaError.fileNotFound(let path) {
    print("File not found: \(path)")
    // Handle gracefully
}
```

**Read-only session:**
```swift
let session = repo.session(commit: commitID)

do {
    try await session.writeFile(data, to: "file.txt")
} catch AkashicaError.sessionReadOnly {
    print("Cannot write to commit session - create workspace first")
}
```

**Branch not found:**
```swift
do {
    let commit = try await repo.currentCommit(branch: "nonexistent")
} catch AkashicaError.branchNotFound(let name) {
    print("Branch '\(name)' does not exist")
    // Create it by publishing workspace
}
```

**Workspace not found:**
```swift
do {
    try await repo.deleteWorkspace(workspaceID)
} catch AkashicaError.workspaceNotFound(let id) {
    print("Workspace \(id.fullReference) already deleted")
}
```

**Scrubbed content:**
```swift
do {
    let data = try await session.readFile(at: "secrets.env")
} catch AkashicaError.objectDeleted(let hash, let tombstone) {
    print("Content deleted: \(tombstone.reason)")
    print("Deleted by: \(tombstone.deletedBy) on \(tombstone.timestamp)")
}
```

**Storage errors:**
```swift
do {
    let commit = try await repo.publishWorkspace(...)
} catch AkashicaError.storageError(let underlyingError) {
    // Could be network error, permission error, etc.
    print("Storage operation failed: \(underlyingError)")
}
```

### Error Recovery Patterns

**Retry on network errors:**

```swift
func robustPublish(
    repo: AkashicaRepository,
    workspace: WorkspaceID,
    maxRetries: Int = 3
) async throws -> CommitID {
    var lastError: Error?

    for attempt in 1...maxRetries {
        do {
            return try await repo.publishWorkspace(
                workspace,
                toBranch: "main",
                message: "Update",
                author: "app"
            )
        } catch AkashicaError.storageError(let err) {
            lastError = err
            print("Publish attempt \(attempt) failed: \(err)")
            try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
        }
    }

    throw lastError ?? AkashicaError.storageError(
        NSError(domain: "RetryExhausted", code: -1)
    )
}
```

**Fallback on missing files:**

```swift
func readConfigWithDefault(
    session: AkashicaSession,
    path: RepositoryPath,
    default: Data
) async -> Data {
    do {
        return try await session.readFile(at: path)
    } catch AkashicaError.fileNotFound {
        return `default`
    } catch {
        print("Unexpected error reading config: \(error)")
        return `default`
    }
}
```

---

## Credential Management

### AWS Credentials for S3 Storage

When using `S3StorageAdapter`, you need AWS credentials. **Never hardcode credentials in your app!**

### Option 1: Environment Variables (Recommended for Development)

```swift
// Set before running app:
// export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
// export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

let storage = try await S3StorageAdapter(
    region: "us-east-1",
    bucket: "my-bucket"
)
// Automatically uses AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
```

### Option 2: AWS Credentials File (Recommended for Shared Environments)

Create `~/.aws/credentials`:

```ini
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

[production]
aws_access_key_id = AKIAPRODUCTION
aws_secret_access_key = wJalrProductionKey
```

```swift
// Uses [default] profile
let storage = try await S3StorageAdapter(
    region: "us-east-1",
    bucket: "my-bucket"
)

// Or specify profile via environment
// export AWS_PROFILE=production
```

### Option 3: IAM Roles (Recommended for Production)

**For EC2/ECS/Lambda:**

```swift
// No credentials needed - IAM role provides them automatically
let storage = try await S3StorageAdapter(
    region: "us-east-1",
    bucket: "my-bucket"
)
// AWS SDK automatically uses instance IAM role
```

**IAM Policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ],
    "Resource": [
      "arn:aws:s3:::my-bucket",
      "arn:aws:s3:::my-bucket/*"
    ]
  }]
}
```

### Option 4: Secure Credential Storage (Recommended for Apps)

**For macOS/iOS apps, use Keychain:**

```swift
import Security

func getAWSCredentials() throws -> (accessKey: String, secretKey: String) {
    // Load from Keychain
    let accessKey = try loadFromKeychain(key: "AWS_ACCESS_KEY_ID")
    let secretKey = try loadFromKeychain(key: "AWS_SECRET_ACCESS_KEY")
    return (accessKey, secretKey)
}

func initializeS3Storage() async throws -> S3StorageAdapter {
    let (accessKey, secretKey) = try getAWSCredentials()

    // Set environment variables (AWS SDK reads these)
    setenv("AWS_ACCESS_KEY_ID", accessKey, 1)
    setenv("AWS_SECRET_ACCESS_KEY", secretKey, 1)

    return try await S3StorageAdapter(
        region: "us-east-1",
        bucket: "my-app-content"
    )
}

func loadFromKeychain(key: String) throws -> String {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: key,
        kSecReturnData as String: true
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess,
          let data = result as? Data,
          let value = String(data: data, encoding: .utf8) else {
        throw KeychainError.notFound
    }

    return value
}
```

### Option 5: Encrypted Embedding with CredentialCode (Recommended for Closed-Source Apps)

**For closed-source macOS/iOS apps** that need to ship with embedded credentials, use [CredentialCode](https://github.com/codelynx/credential-code) - a build-time credential encryption tool.

**Key features:**
- ✅ **AES-256-GCM encryption** - Military-grade security
- ✅ **Build-time generation** - Credentials never committed to source code
- ✅ **Type-safe access** - Swift enums for credential keys
- ✅ **Memory-only decryption** - Credentials only exist in RAM when accessed
- ✅ **No strings in binary** - Credentials don't appear as plain text

**⚠️ IMPORTANT:** CredentialCode is **NOT suitable for open-source projects** because the encryption key is embedded in the binary. Use only for **proprietary/closed-source applications**.

**Setup:**

1. **Install CredentialCode:**
```bash
git clone https://github.com/codelynx/credential-code.git
cd credential-code
swift build -c release
```

2. **Create credentials JSON** (development only, gitignored):
```json
{
  "AWS_ACCESS_KEY_ID": "AKIAIOSFODNN7EXAMPLE",
  "AWS_SECRET_ACCESS_KEY": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  "S3_REGION": "us-east-1",
  "S3_BUCKET": "my-app-content"
}
```

3. **Generate encrypted Swift code** (build phase):
```bash
# Add to Xcode build phase (Run Script)
credential-code \
  --input .credentials/aws.json \
  --output Sources/MyApp/Credentials.swift \
  --language swift
```

4. **Use in your app:**
```swift
import Akashica
import AkashicaS3Storage

func initializeAkashica() async throws -> AkashicaRepository {
    // Decrypt credentials at runtime (memory-only)
    guard let accessKey = Credentials.decrypt(.AWS_ACCESS_KEY_ID),
          let secretKey = Credentials.decrypt(.AWS_SECRET_ACCESS_KEY),
          let region = Credentials.decrypt(.S3_REGION),
          let bucket = Credentials.decrypt(.S3_BUCKET) else {
        throw AppError.credentialDecryptionFailed
    }

    // Set environment variables for AWS SDK
    setenv("AWS_ACCESS_KEY_ID", accessKey, 1)
    setenv("AWS_SECRET_ACCESS_KEY", secretKey, 1)

    // Initialize S3 storage
    let storage = try await S3StorageAdapter(
        region: region,
        bucket: bucket
    )

    return AkashicaRepository(storage: storage)
}
```

**Generated code structure:**
```swift
// Credentials.swift (auto-generated, safe to commit)
enum CredentialKey {
    case AWS_ACCESS_KEY_ID
    case AWS_SECRET_ACCESS_KEY
    case S3_REGION
    case S3_BUCKET
}

struct Credentials {
    static func decrypt(_ key: CredentialKey) -> String? {
        // AES-256-GCM decryption happens here
        // Returns decrypted credential in memory
    }
}
```

**Security benefits over simple obfuscation:**

| Aspect | Simple XOR | CredentialCode |
|--------|-----------|----------------|
| Encryption | Weak (XOR) | Strong (AES-256-GCM) |
| Key storage | Hardcoded | Embedded (not easily extracted) |
| Binary strings | Visible | Not visible |
| Decryption | Always | Only when accessed |
| Type safety | No | Yes (Swift enums) |
| Best for | Nothing | Closed-source apps |

**Alternative secrets management services:**
- AWS Secrets Manager (fetch credentials at runtime from AWS)
- HashiCorp Vault (enterprise secret management)
- 1Password Secrets Automation (CLI-based secret injection)

### Credential Best Practices

1. ✅ **Use IAM roles** for EC2/ECS/Lambda (no credentials in code)
2. ✅ **Use Keychain** for macOS/iOS apps
3. ✅ **Use environment variables** for development
4. ✅ **Use AWS credentials file** for shared machines
5. ✅ **Rotate credentials regularly** (90 days)
6. ✅ **Limit IAM permissions** (principle of least privilege)
7. ❌ **Never commit credentials** to version control
8. ❌ **Never hardcode credentials** in source code
9. ❌ **Never log credentials** (even obfuscated)

---

## Performance Considerations

### Content Deduplication

Akashica automatically deduplicates content by SHA-256 hash:

```swift
// Both files contain identical content
try await session.writeFile(sameData, to: "file1.txt")
try await session.writeFile(sameData, to: "file2.txt")

// Only stored once! (by hash)
// Storage: objects/sha256:abc123... (single copy)
```

**Benefits:**
- Saves storage space (40-60% typical reduction)
- Faster writes (existing content not re-uploaded)
- Efficient moves/renames (COW references)

### Copy-on-Write (COW)

Moving/renaming files uses COW references:

```swift
// Move file
try await session.moveFile(from: "old.txt", to: "new.txt")

// No data copied!
// Storage: refs/new.txt -> {hash: abc123, basePath: "old.txt"}
```

### Lazy Loading

Sessions don't load content upfront:

```swift
let session = repo.session(commit: commitID)
// No network I/O yet

let data = try await session.readFile(at: "large-file.pdf")
// Only now does it fetch the file
```

### Batch Operations

Process multiple files efficiently:

```swift
// BAD: Creates/publishes workspace for each file
for file in files {
    let workspace = try await repo.createWorkspace(fromBranch: "main")
    let session = repo.session(workspace: workspace)
    try await session.writeFile(file.data, to: file.path)
    try await repo.publishWorkspace(workspace, ...)
}

// GOOD: Single workspace for all files
let workspace = try await repo.createWorkspace(fromBranch: "main")
let session = repo.session(workspace: workspace)

for file in files {
    try await session.writeFile(file.data, to: file.path)
}

try await repo.publishWorkspace(workspace, ...)
```

### S3 Performance

**Network latency dominates:**
- Reading small files: ~50-200ms per file
- Writing files: ~100-300ms per file
- Listing directories: ~50ms (paginated)

**Optimization strategies:**

1. **Cache frequently accessed data:**
```swift
actor ContentCache {
    private var cache: [RepositoryPath: Data] = [:]

    func read(
        from session: AkashicaSession,
        at path: RepositoryPath
    ) async throws -> Data {
        if let cached = cache[path] {
            return cached
        }

        let data = try await session.readFile(at: path)
        cache[path] = data
        return data
    }
}
```

2. **Use local storage for temporary workspaces:**
```swift
// Fast editing on local storage
let tempStorage = LocalStorageAdapter(rootPath: tempDir)
let tempRepo = AkashicaRepository(storage: tempStorage)

// Make edits locally (fast)
let workspace = try await tempRepo.createWorkspace(from: baseCommit)
// ... edit files ...

// Publish to S3 (one network operation)
let s3Storage = try await S3StorageAdapter(...)
let s3Repo = AkashicaRepository(storage: s3Storage)
try await s3Repo.publishWorkspace(workspace, ...)
```

3. **Prefetch directory listings:**
```swift
// Prefetch all directories at once
async let rootEntries = session.listDirectory(at: "")
async let docsEntries = session.listDirectory(at: "documents")
async let configEntries = session.listDirectory(at: "config")

let (root, docs, config) = try await (rootEntries, docsEntries, configEntries)
```

### Large Files

**Current limitation:** Files loaded into memory as `Data`:

```swift
// Loads entire file into memory
let data = try await session.readFile(at: "video.mp4")  // ⚠️ 1GB in RAM
```

**Workaround for large files:**

```swift
// For now, keep large files outside Akashica
// Store metadata in Akashica, actual files in S3 directly

struct VideoMetadata: Codable {
    let title: String
    let s3Key: String  // Direct S3 key for video file
    let duration: TimeInterval
}

// Store metadata (small)
let metadata = VideoMetadata(title: "My Video", s3Key: "videos/abc123.mp4", ...)
let data = try JSONEncoder().encode(metadata)
try await session.writeFile(data, to: "videos/abc123.json")

// Access video directly from S3 (not through Akashica)
let videoData = try await s3Client.getObject(bucket: "...", key: metadata.s3Key)
```

**Future:** Streaming API planned for large files.

---

## Testing

### Unit Testing with Local Storage

```swift
import XCTest
import Akashica
import AkashicaStorage

final class MyAppTests: XCTestCase {
    var storage: LocalStorageAdapter!
    var repo: AkashicaRepository!

    override func setUp() async throws {
        // Use temporary directory for tests
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        storage = LocalStorageAdapter(rootPath: tempDir)
        repo = AkashicaRepository(storage: storage)
    }

    override func tearDown() async throws {
        // Clean up test data
        try? FileManager.default.removeItem(at: storage.rootPath)
    }

    func testWorkspaceWorkflow() async throws {
        // Create workspace
        let workspace = try await repo.createWorkspace(from: CommitID(value: "@0"))
        let session = repo.session(workspace: workspace)

        // Write file
        let data = "Test content".data(using: .utf8)!
        try await session.writeFile(data, to: "test.txt")

        // Verify status
        let status = try await session.status()
        XCTAssertEqual(status.added.count, 1)
        XCTAssertEqual(status.added.first?.pathString, "test.txt")

        // Publish
        let commit = try await repo.publishWorkspace(
            workspace,
            toBranch: "main",
            message: "Test commit",
            author: "test@example.com"
        )

        // Verify commit
        let metadata = try await repo.commitMetadata(commit)
        XCTAssertEqual(metadata.message, "Test commit")
        XCTAssertEqual(metadata.author, "test@example.com")
    }
}
```

### Integration Testing with S3

```swift
final class S3IntegrationTests: XCTestCase {
    var storage: S3StorageAdapter!
    var repo: AkashicaRepository!

    override func setUp() async throws {
        // Skip if no AWS credentials
        guard ProcessInfo.processInfo.environment["AWS_ACCESS_KEY_ID"] != nil else {
            throw XCTSkip("AWS credentials not available")
        }

        // Use test bucket with unique prefix
        let testPrefix = "test-\(UUID().uuidString)"
        storage = try await S3StorageAdapter(
            region: "us-east-1",
            bucket: "my-test-bucket",
            keyPrefix: testPrefix
        )
        repo = AkashicaRepository(storage: storage)
    }

    override func tearDown() async throws {
        // Clean up S3 objects (lifecycle policy handles this too)
        // Optional: Manually delete test prefix
    }

    func testS3Publish() async throws {
        let workspace = try await repo.createWorkspace(from: CommitID(value: "@0"))
        let session = repo.session(workspace: workspace)

        try await session.writeFile("S3 test".data(using: .utf8)!, to: "s3-test.txt")

        let commit = try await repo.publishWorkspace(
            workspace,
            toBranch: "main",
            message: "S3 test",
            author: "test"
        )

        // Verify published to S3
        let newSession = try await repo.session(branch: "main")
        let data = try await newSession.readFile(at: "s3-test.txt")
        let content = String(data: data, encoding: .utf8)
        XCTAssertEqual(content, "S3 test")
    }
}
```

### Mock Storage for Unit Tests

```swift
// Create a mock storage adapter for fast unit tests
actor MockStorageAdapter: StorageAdapter {
    private var objects: [ContentHash: Data] = [:]
    private var manifests: [ContentHash: Data] = [:]
    private var branches: [String: BranchPointer] = [:]

    func readObject(hash: ContentHash) async throws -> Data {
        guard let data = objects[hash] else {
            throw AkashicaError.fileNotFound(RepositoryPath(string: hash.value))
        }
        return data
    }

    func writeObject(data: Data) async throws -> ContentHash {
        let hash = ContentHash(data: data)
        objects[hash] = data
        return hash
    }

    // ... implement other methods
}

// Use in tests
func testWithMockStorage() async throws {
    let storage = MockStorageAdapter()
    let repo = AkashicaRepository(storage: storage)

    // Fast tests without filesystem or network I/O
}
```

---

## API Reference

### Quick Reference

**Repository:**
```swift
actor AkashicaRepository {
    // Sessions
    func session(commit: CommitID) -> AkashicaSession
    func session(workspace: WorkspaceID) -> AkashicaSession
    func session(branch: String) async throws -> AkashicaSession

    // Workspaces
    func createWorkspace(from: CommitID) async throws -> WorkspaceID
    func createWorkspace(fromBranch: String) async throws -> WorkspaceID
    func publishWorkspace(_:toBranch:message:author:) async throws -> CommitID
    func deleteWorkspace(_:) async throws

    // Branches
    func branches() async throws -> [String]
    func currentCommit(branch: String) async throws -> CommitID

    // Metadata
    func commitMetadata(_:) async throws -> CommitMetadata
    func commitHistory(branch:limit:) async throws -> [(CommitID, CommitMetadata)]

    // Scrubbing
    func scrubContent(hash:reason:deletedBy:) async throws
    func scrubContent(at:in:reason:deletedBy:) async throws
    func listScrubbedContent() async throws -> [(ContentHash, Tombstone)]
}
```

**Session:**
```swift
actor AkashicaSession {
    // Reading
    func readFile(at: RepositoryPath) async throws -> Data
    func listDirectory(at: RepositoryPath) async throws -> [DirectoryEntry]
    func fileExists(at: RepositoryPath) async throws -> Bool

    // Writing
    func writeFile(_ data: Data, to: RepositoryPath) async throws
    func deleteFile(at: RepositoryPath) async throws
    func moveFile(from: RepositoryPath, to: RepositoryPath) async throws

    // Status
    func status() async throws -> WorkspaceStatus
    func diff(against: CommitID) async throws -> [FileChange]
}
```

**Models:**
```swift
struct CommitID: Hashable, Codable {
    let value: String  // "@1234"
}

struct WorkspaceID: Hashable, Codable {
    let baseCommit: CommitID
    let workspaceSuffix: String
    var fullReference: String  // "@1234$a1b3"
}

struct RepositoryPath: Hashable, Codable, ExpressibleByStringLiteral {
    let components: [String]
    var pathString: String
    var parent: RepositoryPath?
    var name: String?
}

struct CommitMetadata: Codable {
    let message: String
    let author: String
    let timestamp: Date
    let parent: CommitID?
}

struct WorkspaceStatus: Codable {
    let added: [RepositoryPath]
    let modified: [RepositoryPath]
    let deleted: [RepositoryPath]
}

enum FileChange: Codable {
    case added(RepositoryPath)
    case modified(RepositoryPath)
    case deleted(RepositoryPath)
    case typeChanged(RepositoryPath, from: EntryType, to: EntryType)
}

struct DirectoryEntry: Codable {
    let name: String
    let type: EntryType  // .file or .directory
    let hash: ContentHash?
    let size: Int64?
}

struct Tombstone: Codable {
    let deletedHash: String
    let reason: String
    let timestamp: Date
    let deletedBy: String
    let originalSize: Int64
}
```

**Errors:**
```swift
enum AkashicaError: Error {
    case sessionReadOnly
    case workspaceNotFound(WorkspaceID)
    case commitNotFound(CommitID)
    case fileNotFound(RepositoryPath)
    case branchNotFound(String)
    case invalidManifest(String)
    case objectDeleted(hash: ContentHash, tombstone: Tombstone)
    case storageError(Error)
}
```

---

## Conclusion

You now have everything you need to integrate Akashica into your Swift application:

✅ **Understand the two-tier model** - Commits (immutable) vs workspaces (mutable)
✅ **Know the core workflow** - Create workspace → edit → publish → repeat
✅ **Can perform all operations** - Read, write, delete, move, list, scrub
✅ **Handle credentials securely** - Keychain, IAM roles, environment variables
✅ **Write robust code** - Error handling, performance optimization, testing

### Next Steps

1. **Start small** - Integrate with local storage first
2. **Build a prototype** - Implement one content workflow
3. **Add S3** - Scale to cloud storage when ready
4. **Optimize** - Profile and optimize based on real usage
5. **Monitor** - Track storage costs and performance metrics

### Additional Resources

- **[CLI User Guide](CLI_USER_GUIDE.md)** - Command-line tool for repository management
- **[URI Scheme](URI_SCHEME.md)** - `aka://` URI specification
- **[Architecture](ARCHITECTURE.md)** - CLI architecture and design
- **[API Implementation Summary](API_IMPLEMENTATION_SUMMARY.md)** - Internal API details

### Support

- **Issues:** [GitHub Issues](https://github.com/codelynx/akashica/issues)
- **Discussions:** [GitHub Discussions](https://github.com/codelynx/akashica/discussions)
- **Email:** support@example.com (update with actual support email)

---

**Happy coding with Akashica! 🚀**
