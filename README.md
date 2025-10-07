# Akashica

A Swift content management system implementing a dual-tier workspace model with support for local filesystem and AWS S3 storage backends.

## Overview

Akashica provides a Git-like repository system for managing content with:

- **Content-addressed storage** - Files stored and deduplicated by SHA-256 hash
- **Dual-tier model** - Immutable commits + ephemeral workspaces for editing
- **Multiple storage backends** - Local filesystem or AWS S3
- **Type-safe API** - Swift actors for thread-safe concurrent access
- **Full version history** - Commit metadata, branch management, diff support

## Features

### Core Functionality

- ✅ **Commits** - Immutable snapshots with metadata (author, message, timestamp, parent)
- ✅ **Branches** - Named pointers to commits with compare-and-swap updates
- ✅ **Workspaces** - Ephemeral editing sessions based on commits
- ✅ **Copy-on-write** - Efficient file operations with COW references
- ✅ **Nested directories** - Full directory tree support with manifest traversal
- ✅ **Status & diff** - Track changes and compare commits
- ✅ **Commit history** - Navigate version history with parent chains

### Storage Adapters

- **LocalStorageAdapter** - Filesystem-based storage
- **S3StorageAdapter** - AWS S3 cloud storage with pagination and CAS

## Requirements

- Swift 5.9+
- macOS 13+ or iOS 16+
- AWS SDK (optional, only for S3 storage)

## Installation

### Swift Package Manager

Add Akashica to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/akashica.git", from: "1.0.0")
]
```

**For local storage only:**
```swift
.product(name: "Akashica", package: "akashica"),
.product(name: "AkashicaStorage", package: "akashica")
```

**For S3 storage:**
```swift
.product(name: "Akashica", package: "akashica"),
.product(name: "AkashicaS3Storage", package: "akashica")
```

## Quick Start

### Local Storage Example

```swift
import Akashica
import AkashicaStorage

// Initialize with local storage
let storage = LocalStorageAdapter(rootPath: "/path/to/repo")
let repo = AkashicaRepository(storage: storage)

// Create a workspace from initial commit
let workspace = try await repo.createWorkspace(from: "@0")
let session = repo.session(workspace: workspace)

// Make changes
try await session.writeFile("Hello, World!".data(using: .utf8)!, to: "hello.txt")
try await session.writeFile("# README".data(using: .utf8)!, to: "docs/README.md")

// Check status
let status = try await session.status()
print("Added: \(status.added)")  // ["hello.txt", "docs/README.md"]

// Publish to branch
let commit = try await repo.publishWorkspace(
    workspace,
    toBranch: "main",
    message: "Initial commit",
    author: "alice"
)

// Read from any commit
let mainSession = try await repo.session(branch: "main")
let data = try await mainSession.readFile(at: "hello.txt")
print(String(data: data, encoding: .utf8)!)  // "Hello, World!"

// View history
let history = try await repo.commitHistory(branch: "main", limit: 10)
for (commitID, metadata) in history {
    print("\(commitID): \(metadata.author) - \(metadata.message)")
}
```

### S3 Storage Example

```swift
import Akashica
import AkashicaS3Storage

// Initialize with S3 storage
let storage = try await S3StorageAdapter(
    region: "us-east-1",
    bucket: "my-akashica-repo"
)
let repo = AkashicaRepository(storage: storage)

// Same API as local storage - everything else works identically!
let workspace = try await repo.createWorkspace(from: "@0")
// ... (same workflow as above)
```

**Multi-Tenant S3 Storage (Optional):**

```swift
// Isolate multiple repositories in a single S3 bucket
let tenantStorage = try await S3StorageAdapter(
    region: "us-east-1",
    bucket: "shared-bucket",
    keyPrefix: "customer-123"  // All keys prefixed with "customer-123/"
)

// Storage layout: s3://shared-bucket/customer-123/objects/<hash>
//                 s3://shared-bucket/customer-123/branches/main
//                 s3://shared-bucket/customer-456/objects/<hash>  (different tenant)
```

**Note:** The `keyPrefix` parameter enables multi-tenant scenarios where multiple isolated repositories share a single S3 bucket. Each tenant's data is completely isolated by prefix.

## Architecture

### Dual-Tier Model

**Commits (Immutable):**
- Read-only snapshots of the repository at a point in time
- Identified by `@XXXX` (e.g., `@1001`)
- Contain metadata: author, message, timestamp, parent
- Content-addressed storage with SHA-256 hashing

**Workspaces (Ephemeral):**
- Mutable editing sessions based on a parent commit
- Identified by `@XXXX$YYYY` (e.g., `@1001$a1b3`)
- Support write, delete, and move operations
- Can be published to create a new commit, or discarded

### Storage Layout

#### Local Filesystem
```
/repo/
├── objects/<hash>              # Content-addressed files
├── manifests/<hash>            # Directory manifests
├── changeset/@XXXX/
│   ├── root.dir                # Root manifest
│   └── metadata.json           # Commit info
├── changeset/@XXXX$YYYY/
│   ├── workspace.json          # Workspace metadata
│   ├── objects/                # Modified files
│   └── refs/                   # COW references
└── branches/main.json          # Branch pointers
```

#### AWS S3
```
s3://bucket/
├── objects/<hash>
├── manifests/<hash>
├── commits/<commitID>/
│   ├── root-manifest
│   └── metadata.json
├── branches/<name>
└── workspaces/<workspaceID>/
    ├── metadata.json
    ├── files/<path>
    ├── manifests/<path>
    └── cow/<path>
```

## API Reference

### Repository Actor

```swift
actor AkashicaRepository {
    // Session factory
    func session(commit: CommitID) -> AkashicaSession
    func session(workspace: WorkspaceID) -> AkashicaSession
    func session(branch: String) async throws -> AkashicaSession

    // Workspace lifecycle
    func createWorkspace(from: CommitID) async throws -> WorkspaceID
    func createWorkspace(fromBranch: String) async throws -> WorkspaceID
    func deleteWorkspace(_ workspace: WorkspaceID) async throws
    func publishWorkspace(_:toBranch:message:author:) async throws -> CommitID

    // Branch operations
    func branches() async throws -> [String]
    func currentCommit(branch: String) async throws -> CommitID

    // Commit metadata
    func commitMetadata(_ commit: CommitID) async throws -> CommitMetadata
    func commitHistory(branch:limit:) async throws -> [(CommitID, CommitMetadata)]
}
```

### Session Actor

```swift
actor AkashicaSession {
    let changeset: ChangesetRef  // .commit(@1001) or .workspace(@1001$a1b3)
    var isReadOnly: Bool

    // Reading (works for both commits and workspaces)
    func readFile(at: RepositoryPath) async throws -> Data
    func listDirectory(at: RepositoryPath) async throws -> [DirectoryEntry]
    func fileExists(at: RepositoryPath) async throws -> Bool

    // Writing (workspace sessions only)
    func writeFile(_:to:) async throws
    func deleteFile(at:) async throws
    func moveFile(from:to:) async throws

    // Status & diff
    func status() async throws -> WorkspaceStatus
    func diff(against: CommitID) async throws -> [FileChange]
}
```

### Models

```swift
struct CommitID {
    let value: String  // "@1001"
}

struct WorkspaceID {
    let baseCommit: CommitID
    let workspaceSuffix: String
    var fullReference: String  // "@1001$a1b3"
}

enum ChangesetRef {
    case commit(CommitID)
    case workspace(WorkspaceID)
}

struct RepositoryPath {
    let components: [String]
    var pathString: String  // "asia/japan/tokyo.txt"
}

struct CommitMetadata {
    let message: String
    let author: String
    let timestamp: Date
    let parent: CommitID?
}

struct WorkspaceStatus {
    let added: [RepositoryPath]
    let modified: [RepositoryPath]
    let deleted: [RepositoryPath]
}

enum FileChange {
    case added(RepositoryPath)
    case modified(RepositoryPath)
    case deleted(RepositoryPath)
    case typeChanged(RepositoryPath, from: EntryType, to: EntryType)
}
```

## Development

### Building

```bash
swift build
```

### Running Tests

#### Core Tests (No AWS Required)

```bash
swift test
# Runs 138 core tests
# S3 tests automatically skipped without credentials
```

#### S3 Integration Tests

```bash
# 1. Setup credentials template
./configure.sh

# 2. Edit .credentials/aws-credentials.json with your AWS credentials
{
  "accessKeyId": "AKIAIOSFODNN7EXAMPLE",
  "secretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  "region": "us-east-1",
  "bucket": "my-test-bucket"
}

# 3. Create S3 bucket (if needed)
aws s3 mb s3://my-test-bucket

# 4. Configure lifecycle policy for automatic test cleanup
aws s3api put-bucket-lifecycle-configuration --bucket my-test-bucket --lifecycle-configuration '{
  "Rules": [{
    "Id": "DeleteTestRuns",
    "Status": "Enabled",
    "Prefix": "test-runs/",
    "Expiration": { "Days": 1 }
  }]
}'

# 5. Run all tests including S3
swift test
# Runs 160 tests (148 core + 12 S3 integration)
```

**Notes:**
- S3 tests are automatically skipped if `.credentials/aws-credentials.json` doesn't exist
- Each test run uses a unique UUID prefix (`test-runs/<uuid>/`) for isolation
- Lifecycle policy automatically deletes test artifacts after 1 day
- Multiple test runs can execute concurrently without conflicts
- Credentials file is gitignored for security

### Project Structure

```
akashica/
├── Sources/
│   ├── Akashica/              # Core API (actors, models, protocols)
│   ├── AkashicaCore/          # Internal utilities
│   ├── AkashicaStorage/       # Local filesystem adapter
│   └── AkashicaS3Storage/     # AWS S3 adapter
├── Tests/
│   ├── AkashicaTests/         # Core tests (138 tests)
│   ├── AkashicaStorageTests/  # Storage adapter tests
│   ├── AkashicaS3StorageTests/ # S3 integration tests (12 tests)
│   └── TestSupport/           # Shared test helpers
├── docs/                      # Design documentation
├── configure.sh               # Credential setup script
└── Package.swift              # Swift package manifest
```

## CLI Tool

Akashica includes a command-line interface for repository management using the **aka:// URI scheme** for explicit path addressing.

**📖 For comprehensive documentation, see the [CLI User Guide](docs/CLI_USER_GUIDE.md)** - a complete guide for technical directors and content management teams covering:
- Interactive initialization with guided setup
- Storage configuration (local and S3)
- Understanding the two-tier model
- URI scheme and explicit addressing
- Common workflows and best practices
- Troubleshooting and FAQ

### URI Scheme

All file paths use `aka://` URIs to specify exactly where content should be read from or written to:

```bash
aka:/path              # Relative to current virtual working directory
aka:///path            # Absolute path from repository root
aka://main/path        # Read from branch 'main'
aka://@1234/path       # Read from commit @1234
```

### Common Commands

**Initialize repository:**
```bash
akashica init                              # Interactive setup (prompts for local or S3)
akashica init --s3-bucket my-bucket        # Non-interactive S3 mode
akashica init --repo /path/to/repo         # Non-interactive local mode
```

**Workspace management:**
```bash
akashica checkout main                     # Create workspace from branch
akashica status                            # Show working tree status
akashica commit -m "Add feature"           # Commit changes
```

**File operations:**
```bash
# Copy files to/from repository
akashica cp file.txt aka:/draft.txt        # Upload to workspace
akashica cp aka:/draft.txt file.txt        # Download from workspace
akashica cp aka://main/config.yml .        # Download from branch

# Repository operations
akashica cat aka:/file.txt                 # Display file contents
akashica cat aka://main/README.md          # Read from branch
akashica cat aka://@1234/data.json         # Read from commit

akashica ls aka:/                          # List current directory
akashica ls aka:///projects/               # List absolute path
akashica ls aka://main/                    # List branch contents

akashica mv aka:/old.txt aka:/new.txt      # Rename file
akashica rm aka:/draft.pdf                 # Delete file
```

**Navigation:**
```bash
akashica pwd                               # Print virtual working directory
akashica cd aka:/tokyo                     # Change directory
akashica cd aka:///japan/tokyo             # Absolute path
```

**History and branches:**
```bash
akashica log                               # Show commit history
akashica branch                            # List branches
akashica diff                              # Show workspace changes
akashica diff aka:/file.txt                # Show changes for specific file
```

### Key Features

- **Explicit scope targeting**: URIs make it clear whether you're accessing workspace, branch, or commit
- **No path ambiguity**: `aka:/tokyo/data.txt` is always relative, `aka:///tokyo/data.txt` is always absolute
- **Read from any ref**: Commands like `cat` and `ls` can read from branches and commits directly
- **Write validation**: Write operations automatically validate that the target is writable (workspace only)

See [docs/URI_SCHEME.md](docs/URI_SCHEME.md) for complete URI specification.

## Documentation

Comprehensive documentation is available in the `docs/` directory:

**For Users:**
- **[CLI_USER_GUIDE.md](docs/CLI_USER_GUIDE.md)** - Complete guide for technical directors and content teams (start here!)
- **[URI_SCHEME.md](docs/URI_SCHEME.md)** - aka:// URI specification and examples

**For Developers:**
- **[ARCHITECTURE.md](docs/ARCHITECTURE.md)** - Session-first CLI architecture
- **[API_IMPLEMENTATION_SUMMARY.md](docs/API_IMPLEMENTATION_SUMMARY.md)** - Library API reference
- **[design.md](docs/design.md)** - Core architecture and storage format
- **[two-tier-commit.md](docs/two-tier-commit.md)** - Dual-tier workspace model
- **[WORKSPACE_DESIGN_SUMMARY.md](docs/WORKSPACE_DESIGN_SUMMARY.md)** - Workspace implementation

## Use Cases

### Content Management System
Store and version content files (text, JSON, images) with full history tracking.

### Configuration Management
Track configuration changes across environments with branching and rollback support.

### Multi-User Collaboration
Independent workspaces allow multiple users to edit simultaneously without conflicts.

### Cloud-Native Applications
Use S3 storage for globally distributed, scalable content repositories.

## Roadmap

### Completed ✅
- Core repository operations
- Local filesystem storage
- AWS S3 storage with pagination
- Nested directory support
- Commit history and metadata
- Status and diff functionality
- Comprehensive test suite (150 tests)

### Future Enhancements
- Google Cloud Storage adapter
- Streaming API for large files (>1GB)
- Merge conflict resolution
- Rename detection in diffs
- Garbage collection for unused objects
- Performance benchmarks

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass: `swift test`
5. Submit a pull request

## License

[Your License Here]

## Acknowledgments

Built with:
- [AWS SDK for Swift](https://github.com/awslabs/aws-sdk-swift) - S3 storage backend
- Swift Concurrency - Actor-based thread safety
- CryptoKit - SHA-256 content addressing

## Support

- Issues: [GitHub Issues](https://github.com/yourusername/akashica/issues)
- Documentation: [docs/](./docs/)
- Design Documents: See `docs/design.md` and `docs/two-tier-commit.md`
