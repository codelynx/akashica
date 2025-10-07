# Akashica

A Swift-based content-addressed repository system with Git-like semantics, optimized for large binary assets.

## Features

- **Dual-tier commits**: Immutable branch heads (`@1002`) for published history, ephemeral workspace commits (`@1002$a1b3`) for in-progress changes
- **Copy-on-write**: Manifest reuse and COW references prevent storage bloat from renames/copies
- **Storage-agnostic**: Pluggable storage adapters (local filesystem, future: S3, GCS)
- **Session-based API**: Independent, stateful sessions tied to specific changesets
- **Content-addressed**: SHA-256 hashing with automatic object deduplication
- **Compare-and-swap**: Optimistic concurrency control for branch pointer updates

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/yourorg/akashica", from: "0.1.0")
]
```

## Usage

```swift
import Akashica
import AkashicaStorage

// Create repository with local storage
let storage = LocalStorageAdapter(rootPath: URL(fileURLWithPath: "/path/to/repo"))
let repo = AkashicaRepository(storage: storage)

// Create workspace from main branch
let workspaceID = try await repo.createWorkspace(fromBranch: "main")
let session = repo.session(workspace: workspaceID)

// Edit files
try await session.writeFile(
    data,
    to: RepositoryPath(string: "documents/readme.txt")
)

// Check status
let status = try await session.status()
print("Modified: \(status.modified.count)")

// Publish changes
let newCommit = try await repo.publishWorkspace(
    workspaceID,
    toBranch: "main",
    message: "Update documentation"
)
```

## Documentation

- [Design Document](docs/design.md) - Storage format, manifest schema, and commit workflow
- [Workspace Model](docs/two-tier-commit.md) - Dual-tier model with lifecycle details and COW optimization
- [Design Summary](docs/WORKSPACE_DESIGN_SUMMARY.md) - Concise reviewer summary
- [Storage Samples](docs/samples/) - Step-by-step physical storage structure examples

## Project Status

🚧 **Early Development** - API design phase. Core types and protocols implemented, full functionality in progress.

## License

[Your License Here]
