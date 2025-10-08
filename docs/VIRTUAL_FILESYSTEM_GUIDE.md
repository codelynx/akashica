# Virtual Filesystem

**Version**: 1.0
**Last Updated**: 2025-10-08
**Applies to**: Akashica v0.10.0+

## Overview

Akashica provides a virtual filesystem interface for navigating and manipulating content in remote repositories without requiring full local checkouts. This enables working with petabyte-scale repositories while maintaining minimal local storage footprint.

## Core Concept

### Separation of Concerns

Akashica separates **working directory** from **content storage**:

**Traditional VCS** (Git-like):
- Clone entire repository locally
- Working directory = local copy of repository
- Edits happen directly in filesystem
- Limited by local disk capacity

**Akashica** (Virtual filesystem):
- Working directory is thin client (no content)
- Repository content stays remote (NAS/S3)
- Virtual navigation of remote content
- Scales to petabyte repositories

### Target Use Case

**Publishing Division Technical Director**:
- Manages multi-terabyte content (PDFs, videos, images)
- Needs version control for content
- Content larger than local storage capacity
- Uses combination of NAS and S3 storage
- Requires separation of shell working directory from repository

## Virtual Filesystem Commands

### Navigation

Commands for exploring repository structure:

```bash
akashica ls [aka:path]     # List directory contents
akashica cat aka:path      # Stream file content to stdout
akashica cd path           # Change virtual working directory
akashica pwd               # Print virtual working directory
```

**All operations use virtual CWD** as base for relative paths.

**Example session**:
```bash
$ akashica checkout main
Created workspace @1$ws_a3f2

$ akashica pwd
/

$ akashica ls
docs/
videos/
images/

$ akashica cd docs
$ akashica pwd
/docs

$ akashica ls
manual.pdf  (2.4M)
guide.pdf   (1.8M)

$ akashica cat aka:manual.pdf | head -10
[PDF content streamed from remote storage...]
```

### Content Operations

Commands bridging local filesystem and repository:

```bash
akashica cp <local> aka:<remote>   # Upload to repository
akashica cp aka:<remote> <local>   # Download from repository
akashica rm aka:<path>             # Delete in workspace
akashica mv aka:<from> aka:<to>    # Move/rename in workspace
```

**Local paths** resolved from shell CWD (explicit I/O).
**Repository paths** resolved from virtual CWD.

**Example workflow**:
```bash
$ cd ~/Desktop
$ akashica cp video.mp4 aka:/videos/intro.mp4
Staged: /videos/intro.mp4

$ akashica cp aka:/docs/manual.pdf ~/Desktop/manual.pdf
Downloaded: ~/Desktop/manual.pdf

$ akashica rm aka:/videos/old.mp4
Deleted: /videos/old.mp4

$ akashica mv aka:/draft.txt aka:/published.txt
Moved: /draft.txt → /published.txt
```

## Workspace as Staging Area

### Remote Workspace Model

**The workspace IS the staging area** - modifications stored remotely, not locally.

**For local storage** (NAS):
- Workspace changeset stored in repository
- Manifest deltas tracked
- Operations modify repository directly

**For S3 storage**:
- Workspace changeset stored in S3
- Cloud-native workflow
- Requires connectivity for write operations

**Benefits**:
- Minimal local footprint (no local staging directory)
- Consistent behavior across storage backends
- Leverages existing `AkashicaSession` API

**Trade-offs**:
- Write operations require connectivity
- Remote latency (acceptable for PDFs/images)

### Staging Workflow

```bash
# Create workspace from branch
$ akashica checkout main
Created workspace @1045$ws_a3f2

# Stage changes (operations modify remote workspace)
$ akashica cp ~/file1.pdf aka:/docs/file1.pdf
Staged: /docs/file1.pdf

$ akashica cp ~/file2.pdf aka:/docs/file2.pdf
Staged: /docs/file2.pdf

$ akashica rm aka:/docs/old.pdf
Deleted: /docs/old.pdf

# Check staged changes
$ akashica status
Added files:
  + /docs/file1.pdf
  + /docs/file2.pdf

Deleted files:
  - /docs/old.pdf

# Publish changes atomically
$ akashica commit -m "Update documentation"
[main @1046] Update documentation
```

**Key behaviors**:
- Each operation modifies remote workspace immediately
- `status` shows workspace changes vs base commit
- `commit` publishes workspace as new commit
- Old workspace deleted after successful commit

## Path Resolution

### aka:// URI Scheme

Explicit repository path scoping.

**Syntax**:
```
aka:/absolute/path       # Absolute path (starts with /)
aka:relative/path        # Relative path (no leading /)
aka:.                    # Current virtual CWD
aka:..                   # Parent of virtual CWD
```

### Absolute Paths

Always resolve to same location, ignoring virtual CWD:

```bash
$ akashica pwd
/marketing

$ akashica cat aka:/docs/manual.pdf  # ← Absolute
# Reads /docs/manual.pdf (not /marketing/docs/manual.pdf)
```

### Relative Paths

Resolved from virtual CWD:

```bash
$ akashica pwd
/marketing

$ akashica cat aka:logo.png  # ← Relative
# Reads /marketing/logo.png

$ akashica cat aka:../docs/manual.pdf  # ← Relative with ..
# Reads /docs/manual.pdf
```

### Path Normalization

Handles special segments:

- `.` - Current directory (no-op)
- `..` - Parent directory (pops component)
- `//` - Duplicate slashes (removed)

**Examples**:
```bash
/docs/./manual.pdf       → /docs/manual.pdf
/docs/../videos/intro.mp4 → /videos/intro.mp4
/docs//subdir/file.txt   → /docs/subdir/file.txt
```

**At root boundary**:
```bash
/../file.txt  → /file.txt  # .. at root has no effect
```

## Virtual CWD Persistence

### Cross-Command Persistence

Virtual CWD persists across commands and terminal sessions:

```bash
# Terminal A
$ export AKASHICA_PROFILE=my-profile
$ akashica cd /docs/reports
$ akashica pwd
/docs/reports

# Terminal B (different shell process)
$ export AKASHICA_PROFILE=my-profile
$ akashica pwd
/docs/reports  # ← Persisted from Terminal A
```

**Storage**: `~/.akashica/workspaces/{profile}/state.json`

```json
{
  "profile": "my-profile",
  "workspaceId": "@1045$ws_a3f2",
  "baseCommit": "@1045",
  "virtualCwd": "/docs/reports",  // ← Persisted state
  "view": {
    "active": false,
    "commit": null
  }
}
```

### Shell Independence

Virtual CWD **completely independent** of shell CWD:

```bash
$ export AKASHICA_PROFILE=my-profile
$ akashica pwd
/docs  # ← Virtual CWD

$ pwd
/tmp   # ← Shell CWD (different!)

$ cd ~/Desktop
$ akashica pwd
/docs  # ← Virtual CWD unchanged

$ akashica ls
# Lists /docs contents (not ~/Desktop contents)
```

**Why this matters**:
- Shell location irrelevant to repository operations
- Safe by design (no accidental filesystem scanning)
- Commands work from any shell directory

## View Mode

### Read-Only Historical Inspection

View mode enables browsing historical commits without affecting workspace.

**Enter view mode**:
```bash
$ akashica view @1032
Entered read-only view mode at @1032
Virtual CWD: /

All commands now operate in this view context.
To exit view mode: akashica view --exit
```

**Browse historical content**:
```bash
$ akashica ls aka:/docs/
manual-v1.pdf  (1.2M)
guide-v1.pdf   (800K)

$ akashica cat aka:/docs/manual-v1.pdf
[Historical content from @1032...]

$ akashica cd /docs
$ akashica pwd
/docs  # ← Virtual CWD in view mode
```

**Write operations fail**:
```bash
$ akashica cp ~/file.txt aka:/new.txt
Error: Cannot modify files in view mode
```

**Exit view mode**:
```bash
$ akashica view --exit
Exited view mode

Run 'akashica checkout <branch>' to create a workspace
```

### View Mode State

View mode state persisted in workspace state:

**In view mode**:
```json
{
  "profile": "my-profile",
  "workspaceId": "@1045$ws_a3f2",
  "baseCommit": "@1045",
  "virtualCwd": "/docs/reports",
  "view": {
    "active": true,           // ← View mode active
    "commit": "@1032",        // ← Viewing this commit
    "startedAt": "2025-10-08T15:00:00Z"
  }
}
```

**After exit**:
```json
{
  "profile": "my-profile",
  "workspaceId": "@1045$ws_a3f2",
  "baseCommit": "@1045",
  "virtualCwd": "/docs/reports",  // ← Preserved
  "view": {
    "active": false,          // ← Back to workspace
    "commit": null
  }
}
```

**Key behaviors**:
- Workspace context preserved during view mode
- Virtual CWD maintained
- Exit restores workspace seamlessly

## References

- **Profile Architecture**: `docs/PROFILE_ARCHITECTURE.md`
- **Getting Started Guide**: `docs/CLI_GETTING_STARTED.md`
- **User Guide**: `docs/CLI_USER_GUIDE.md`
