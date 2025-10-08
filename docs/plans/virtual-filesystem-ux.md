# Virtual Filesystem UX Vision

**Date**: 2025-10-07
**Status**: HISTORICAL - See implementation notes below
**Implementation**: Core vision achieved in v0.10.0 with architectural improvements

---

## ⚠️ IMPLEMENTATION NOTE

This document represents the **initial brainstorming** for the virtual filesystem UX. The core vision has been **successfully implemented in v0.10.0**, but with significant architectural improvements:

### What Changed from This Document

**Original concept** (this document):
- `.akashica/config` file in each working directory
- Commands like `akashica ls /path` (no URI scheme)
- Per-directory configuration

**Actual v0.10.0 implementation** (better):
- **Zero working directory pollution** - All config in `~/.akashica/`
- **Profile-based architecture** - `AKASHICA_PROFILE` environment variable
- **aka:// URI scheme** - Explicit path scoping (e.g., `aka:/docs/file.txt`)
- **Shell independence** - Commands work from any directory
- **Per-profile workspace state** - `~/.akashica/workspaces/{profile}/state.json`

### Core Vision: ✅ Achieved

The fundamental goals are all met:
- ✅ Separate working directory from content storage
- ✅ Virtual filesystem navigation (`ls`, `cd`, `cat`, `pwd`)
- ✅ Thin client (minimal local footprint)
- ✅ Workspace as staging area for changes
- ✅ Content stays remote, no massive local checkouts

**For the actual implemented architecture, see**: `docs/plans/environment-based-context.md`

---

## Original Planning Document (Historical)

## Background

The current Akashica CLI follows a Git-like UX where the repository, working directory, and storage are tightly coupled. This document explores an alternative UX vision where Akashica operates as a virtual filesystem over massive-scale content stores (multi-terabyte to petabyte scale).

## User Persona

**Technical Director of Publishing Contents Division**
- Manages multi-terabyte scale content
- Needs to work with content larger than local storage capacity
- Wants to use combination of local (NAS) and cloud (S3) storage
- Prefers working directory separate from content storage

## Current UX (Git-like)

- Repository = Working Directory = Storage
- `.akashica/` is local metadata + content storage
- User manages actual files in filesystem
- CLI wraps version control around existing files

**Workflow**:
```bash
cd ~/Documents/MyContents/
akashica init
# .akashica/ created here, content stored here
akashica checkout main
# Files materialized in working directory
echo "hello" > file.txt
akashica commit -m "Add file"
```

## Proposed UX (Virtual Filesystem)

### Core Concept

Separate the working directory from content storage:
- `~/Documents/MyContents/` = thin configuration directory
- Actual storage = elsewhere (NAS, S3, multi-TB/PB scale)
- `.akashica/config` holds storage backend configuration
- Working directory provides virtual navigation of remote content

### User Workflow

```bash
cd ~/Documents/MyContents/
akashica init --storage s3 --bucket company-assets

# Credentials stored in .akashica/config (not global)

# Create workspace (= staging area in S3)
akashica checkout main                      # Creates remote workspace from branch head

# Virtual filesystem operations (operate on remote workspace)
akashica ls /japan/tokyo/                   # List directory in workspace
akashica cat /japan/tokyo/banana.txt        # Stream file from workspace
akashica cd /japan/tokyo/                   # Virtual navigation (CLI state only)
akashica cp ~/Desktop/banana.txt banana.txt # Upload to workspace immediately
akashica cp banana.txt ~/Desktop/           # Download from workspace
akashica rm old-file.txt                    # Delete in workspace immediately
akashica mv a.txt b.txt                     # Move in workspace immediately

# Version control operations
akashica status                             # Show workspace changes vs base commit
akashica commit -m "Add Tokyo content"      # Publish workspace as new commit
akashica log                                # Show commit history
```

### Key Architectural Insight: Workspace = Staging Area

**The existing `AkashicaSession` API already provides virtual filesystem semantics!**

- **Workspace** acts as the staging area (remote, in S3)
- Write operations (`cp`, `rm`, `mv`) → directly modify S3 workspace
- Read operations (`ls`, `cat`) → stream from S3 (commit or workspace)
- `status()` → shows workspace changes vs base commit
- `publishWorkspace()` → atomic commit to branch

**Trade-offs**:
- ✅ Simpler: No local staging layer, no `.akashica/staging/` directory
- ✅ Cloud-native: Changes reflected immediately in remote workspace
- ✅ Low local footprint: Only config + virtual CWD stored locally
- ⚠️ Requires connectivity: Every `cp`/`rm`/`mv` touches S3 (acceptable for PDFs/images)
- ⚠️ Remote latency: Operations are not instant (but tolerable for target use case)

**Optional local read cache** (post-MVP):
- Cache results of `readFile()` to avoid repeated S3 fetches
- Cache location: `.akashica/cache/`
- Eviction: LRU when size limit reached
- Cache validity: Content-addressed (hash-based), never stale

### Key Differences from Git

| Aspect | Git Model | Virtual Filesystem Model |
|--------|-----------|-------------------------|
| **Content location** | Clone entire repo locally | Content stays remote |
| **Working directory** | Full copy of files | Thin config + staging area |
| **File access** | Direct filesystem access | Virtual paths, stream on-demand |
| **Scale** | Limited by local disk | Petabyte-scale remote storage |
| **Checkout** | Downloads all files | Switches branch pointer only |
| **Cache** | N/A (all local) | Smart caching for accessed content |

## Architecture Changes

### Current Architecture

```
User ←→ CLI ←→ Repository Actor ←→ Storage (local .akashica/)
                                          ↓
                                    User's files in FS
```

### Proposed Architecture

```
User ←→ CLI ←→ Repository Actor ←→ Storage (S3/NAS)
         ↓                              ↓
    .akashica/                    Content Cache
    - config                       (optional)
    - BRANCH
    - WORKSPACE (pending changes)
    - CWD (virtual path)
```

## Command Set

### Virtual Filesystem Commands

```bash
akashica ls [path]              # List remote tree
akashica cat <path>             # Stream content to stdout
akashica cp <src> <dst>         # Copy local↔remote
akashica rm <path>              # Stage deletion
akashica mv <src> <dst>         # Stage move/rename
akashica cd <path>              # Change virtual working directory
akashica pwd                    # Show current virtual directory
akashica tree [path]            # Show directory tree
akashica du [path]              # Show disk usage
```

### Version Control Commands (reinterpreted)

```bash
akashica init [--storage type]  # Initialize config directory
akashica checkout <branch>      # Switch branch (updates virtual view)
akashica status                 # Show pending changes (staged operations)
akashica commit -m "msg"        # Publish staged changes
akashica log                    # Show commit history
akashica branch                 # List branches
akashica diff                   # Show pending changes
```

### Configuration Commands

```bash
akashica config <key> <value>   # Set configuration
akashica config --list          # List all configuration
```

## Path Semantics

Need to distinguish between local filesystem paths and repository virtual paths.

### Option 1: Prefix-based (like scp)
```bash
akashica cp local:~/Desktop/file.txt remote:/japan/tokyo/file.txt
akashica cp remote:/japan/tokyo/file.txt local:~/Desktop/file.txt
```

### Option 2: Implicit (based on path format)
```bash
# Paths starting with / = repository paths
# Paths without / or starting with ~/ or ./ = local paths
akashica cp ~/Desktop/file.txt /japan/tokyo/file.txt
akashica cp /japan/tokyo/file.txt ~/Desktop/file.txt
```

### Option 3: Context-aware
```bash
# When in virtual directory (after akashica cd), relative paths are remote
akashica cd /japan/tokyo/
akashica cp ~/Desktop/file.txt .          # Local → Remote
akashica cp banana.txt ~/Desktop/         # Remote → Local
```

## Configuration File

`.akashica/config` example (JSON format):

```json
{
  "repository": {
    "name": "company-assets",
    "version": "1.0"
  },
  "storage": {
    "type": "s3",
    "bucket": "company-assets-prod",
    "region": "us-west-2",
    "prefix": "content/",
    "credentials": {
      "mode": "chain"
    }
  },
  "cache": {
    "enabled": false,
    "local_path": "/Volumes/NAS/akashica-cache",
    "max_size": "500GB"
  },
  "ui": {
    "color": true,
    "progress": false
  }
}
```

**Security Note**: Add `.akashica/config` to your `.gitignore` if it contains credentials:
```gitignore
# .gitignore
.akashica/config
.akashica/staging/
.akashica/cache/
```

**Credential modes**:
- `"mode": "chain"` - Use AWS credential chain (recommended)
- `"mode": "static"` - Use explicit keys in config:
  ```json
  "credentials": {
    "mode": "static",
    "access_key_id": "AKIAIOSFODNN7EXAMPLE",
    "secret_access_key": "wJalrXUt..."
  }
  ```

## Open Questions

### 1. Workspace Model

When user does `akashica cp ~/Desktop/banana.txt /japan/tokyo/banana.txt`:

**Option A**: Upload immediately to S3
- Pros: Simple, immediate feedback
- Cons: Large files block CLI, no batching, no rollback

**Option B**: Stage in local workspace, upload on commit
- Pros: Atomic commits, can review before publish, batching
- Cons: Requires local disk space for staging, delayed upload

**Recommendation**: Option B (Git-like staging) for consistency with version control semantics

### 2. Content Streaming

When user does `akashica cat /japan/tokyo/banana.txt`:

**Option A**: Stream directly from S3
- Pros: No disk space needed, always fresh
- Cons: Network latency, bandwidth costs

**Option B**: Cache locally, then stream
- Pros: Faster subsequent access, offline capability
- Cons: Disk space, cache invalidation complexity

**Recommendation**: Option B with smart caching (configurable)

### 3. Large Operations

Initial focus on PDFs and images; video/100GB directories are out of scope for MVP.

For staged files (PDFs/images):
- Stage locally in `.akashica/staging/`
- Upload on commit
- Show progress bars for multi-file operations
- Defer resumable/parallel uploads to post-MVP

### 4. Configuration Scope

**Decision**: Per-directory only (`.akashica/config`)

Rationale:
- Avoids user error from global config affecting multiple projects
- Credentials stored locally in working directory (not global)
- Each project is self-contained and explicit
- Simpler mental model: everything is in `.akashica/`

No global config file.

### 5. Multi-user Coordination

**Key insight**: No conflict resolution needed because:
- Committed changesets are immutable (read-only)
- Each user has their own local workspace (not shared)
- Workspaces are private staging areas before commit

**Workflow**:
```bash
# User A
akashica cp ~/file.txt /path/file.txt
akashica commit -m "Add file"        # Creates new commit @abc

# User B (in different location, independent workspace)
akashica checkout main               # Sees User A's commit
akashica ls /path/                   # Sees file.txt immediately
akashica cp ~/other.txt /path/other.txt
akashica commit -m "Add other"       # Creates commit @def (parent: @abc)
```

No `pull` or `merge` needed - commits are linear and atomic. Branch updates are atomic CAS operations at storage layer.

## Implementation Phases

### Phase 1: Configuration System (MVP)
- Config file parsing (JSON or simple key-value) - local only (`.akashica/config`)
- Storage backend configuration (S3, local)
- Authentication modes:
  - **AWS credential chain** (recommended): Environment vars, `~/.aws/credentials`, IAM roles
  - **Static keys** (fallback): Stored in `.akashica/config`
- Security: `.akashica/config` should be added to `.gitignore` if credentials are stored
- Note: Encryption of config file is post-MVP (users should use credential chain for production)

### Phase 2: Virtual Filesystem Core (MVP)
- Virtual current directory state (stored in `.akashica/CWD`)
- Path resolution (relative → absolute based on CWD)
- `ls` → `session.listDirectory()`
- `cat` → `session.readFile()` (stream to stdout)
- `cd` → Update `.akashica/CWD` file
- `pwd` → Read `.akashica/CWD` file
- Error message wrapping (`.fileNotFound` → "File not found in virtual filesystem")

### Phase 3: Content Operations (MVP)
- `cp local remote` → Read local file, call `session.writeFile()` (uploads to S3 workspace)
- `cp remote local` → Call `session.readFile()`, write to local filesystem
- `rm` → `session.deleteFile()` (deletes from S3 workspace)
- `mv` → `session.moveFile()` (rename/move in S3 workspace)
- Progress indication for uploads (optional, can be deferred)

**No local staging needed** - operations modify remote workspace directly.

**Mapping from current CLI behavior**:
- Current `checkout`: Downloads files to working directory → **New**: Creates remote workspace, stores workspace ID in `.akashica/WORKSPACE`
- Current `status`: Reads filesystem changes → **New**: Calls `session.status()` on remote workspace
- Current `commit`: Uploads modified files → **New**: Calls `repo.publishWorkspace()` (already atomic)
- Current `cp`: N/A → **New**: `session.writeFile()` for local→remote, `session.readFile()` for remote→local

### Phase 4: Integration with Version Control (MVP)
- `checkout <branch>` → `repo.createWorkspace(fromBranch:)`, save workspace ID to `.akashica/WORKSPACE`
- `status` → `session.status()`, format output (added/modified/deleted)
- `commit -m "msg"` → `repo.publishWorkspace()`, clear `.akashica/WORKSPACE`
- All commands use existing Repository/Session APIs - no new library code needed!

### Phase 5: Advanced Features (Post-MVP)
- Local cache for read operations (`.akashica/cache/`)
- Progress reporting for multi-file operations
- Network failure handling and retries
- `akashica cache clean`, `akashica cache status` commands

## Impact on Existing Library

**Zero library changes needed!** 🎉

The existing `AkashicaSession` API already provides everything:
- ✅ `listDirectory()` → virtual `ls`
- ✅ `readFile()` → virtual `cat` (streaming)
- ✅ `writeFile()` → virtual `cp` (local→remote)
- ✅ `deleteFile()` → virtual `rm`
- ✅ `moveFile()` → virtual `mv`
- ✅ `status()` → show workspace changes
- ✅ `diff()` → compare changesets

**All implementation is in the CLI layer** (`Sources/AkashicaCLI/`):
- Virtual CWD tracking (`.akashica/CWD` file)
- Path resolution (relative → absolute)
- Error message formatting
- Local file I/O (for `cp local→remote` and `remote→local`)
- Optional read cache (post-MVP)

## Comparison with Similar Tools

### Git
- Full clone model
- Local-first workflow
- Not designed for TB/PB scale

### Git LFS
- Large file support via pointers
- Still requires checkout
- Limited virtual filesystem semantics

### S3FS / rclone
- Virtual filesystem mount
- No version control
- No staging/commit workflow

### Akashica (proposed)
- Virtual filesystem semantics
- Version control (commits, branches)
- Designed for petabyte scale
- Staging workflow like Git
- Content-addressable storage

## Clarifications from Feedback

### Scope Decisions

1. **File sizes**: Start with PDFs and images; defer large video files (100GB+) to post-MVP
2. **Configuration**: Local only (`.akashica/config`), no global config to prevent user errors
3. **Credentials**: Stored in working directory config, not global
4. **Caching**: Post-MVP feature; initial version streams directly from S3
5. **Network failures**: Post-MVP; focus on basic functionality first
6. **Multi-user**: No conflict resolution needed - workspaces are private, commits are immutable

### MVP Focus

The MVP focuses on core virtual filesystem semantics:
- Navigate remote content without downloading (`ls`, `cd`, `pwd`, `cat`)
- Stage changes locally before commit (`cp`, `rm`, `mv`)
- Publish changes atomically (`commit`)
- Content stays remote, working directory is thin client

Defer optimization (caching, resumable uploads, progress bars) to post-MVP.

### Failure Behavior in MVP

**Stream/download failures** (`cat`, `cp remote→local`):
- Command fails with error message
- No partial output written
- User retries manually
- Post-MVP: Automatic retry with exponential backoff

**Upload failures** (during `cp local→remote` or `commit`):
- If `session.writeFile()` fails during `cp`: Error shown, file not added to workspace
- If `publishWorkspace()` fails during `commit`: Workspace remains intact (not deleted)
- User can inspect with `akashica status`
- User retries operation (operations are idempotent)
- Post-MVP: Progress tracking, automatic retry with backoff

**Branch update conflicts**:
- If branch moved between checkout and commit (CAS failure)
- Error: "Branch 'main' has moved. Run 'akashica checkout main' and retry."
- User re-checkouts and re-applies changes
- Post-MVP: Automatic rebase option

**Partial manifest uploads**:
- Transaction model: Commit only succeeds if ALL parts upload
- Atomicity guaranteed by CAS (Compare-And-Swap) on branch update:
  1. Upload all content chunks (content-addressed, idempotent)
  2. Upload manifest tree (bottom-up)
  3. Write commit metadata
  4. CAS branch pointer: `expected=@old, new=@new`
  5. If CAS fails → rollback is automatic (orphaned objects, no broken state)
- On failure: Storage layer leaves no partial state, user sees clear error and can retry

## Summary: Simpler Architecture

The virtual filesystem UX can be delivered **entirely in the CLI layer** by leveraging the existing `AkashicaSession` API:

1. **Workspace = Staging Area** (remote, in S3)
   - Write operations modify S3 workspace immediately
   - No local `.akashica/staging/` directory needed
   - Cloud-native workflow

2. **Virtual CWD = CLI State** (local `.akashica/CWD` file)
   - `cd`, `pwd` update/read local file
   - Path resolution happens in CLI before calling Session

3. **Session API = Virtual Filesystem**
   - `listDirectory()`, `readFile()`, `writeFile()`, `deleteFile()`, `moveFile()`
   - Already supports everything needed
   - No library changes required

**Benefits**:
- ✅ Drastically simpler implementation
- ✅ Faster path to MVP
- ✅ Leverages existing, tested APIs
- ✅ True cloud-native workflow
- ✅ Minimal local footprint

**Trade-offs**:
- ⚠️ Requires connectivity for write operations (acceptable for target use case)
- ⚠️ Remote latency for operations (tolerable for PDFs/images)

## Next Steps

1. **Prototype Phase 1**: Config parsing (JSON) and storage backend selection
2. **Prototype Phase 2**: Virtual CWD tracking + path resolution, wrap Session APIs (`ls`, `cat`, `cd`, `pwd`)
3. **Prototype Phase 3**: Implement `cp` (local I/O + Session), `rm`, `mv` (Session wrappers)
4. **Integrate Phase 4**: Update `checkout`, `status`, `commit` to use workspace model
5. **User testing**: Validate with publishing division use cases (PDFs, images)

## References

- Current CLI implementation: `Sources/AkashicaCLI/`
- Storage abstraction: `Sources/AkashicaStorage/`
- S3 backend: `Sources/AkashicaS3Storage/`
- Original design: `docs/design.md`
