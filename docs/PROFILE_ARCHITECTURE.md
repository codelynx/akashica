# Profile-Based Architecture

**Version**: 1.0
**Last Updated**: 2025-10-08
**Applies to**: Akashica v0.10.0+

## Overview

Akashica v0.10.0 implements a profile-based architecture inspired by AWS CLI, where all configuration and workspace state resides outside working directories. This enables clean working directories, shell-independent operation, and multi-repository workflows.

## Core Principles

### 1. Zero Working Directory Pollution

Working directories contain **only user content**. All Akashica metadata resides elsewhere:

**Working directory** (clean):
```
~/projects/my-work/
└── myfile.txt           # ONLY user content
```

**Global configuration** (`~/.akashica/`):
```
~/.akashica/
├── configurations/
│   ├── nas-video.json   # Profile config
│   └── s3-assets.json   # Profile config
└── workspaces/
    ├── nas-video/
    │   └── state.json   # Workspace state
    └── s3-assets/
        └── state.json
```

**Repository storage** (NAS/S3/local):
```
/Volumes/NAS/repos/video-campaign/
├── .akashica.json       # Repository metadata
├── objects/             # Content-addressed objects
├── branches/            # Branch pointers
└── changeset/           # Workspace changesets
```

### 2. Profile-Based Context Resolution

Context determined by:

1. `--profile` command-line flag (highest priority)
2. `AKASHICA_PROFILE` environment variable
3. Error if neither specified (no default)

```bash
# Terminal A - Video team
export AKASHICA_PROFILE=nas-video
akashica status

# Terminal B - Assets team
export AKASHICA_PROFILE=s3-assets
akashica status
```

### 3. Shell Independence

Commands work from **any directory**:

```bash
$ export AKASHICA_PROFILE=nas-video
$ cd ~/Desktop
$ akashica cp video.mp4 aka:/videos/intro.mp4  # ✓ Works

$ cd /tmp
$ akashica status  # ✓ Still works - context from profile
```

**Why safe**:
- `commit` never scans shell filesystem
- Staging is explicit (via `cp`, `mv`, `rm`)
- Shell location decoupled from repository operations

### 4. Dual Path Model

Two independent path contexts:

1. **Shell CWD** - Where process runs
   - Used for local file I/O
   - Never tracked by Akashica

2. **Virtual CWD** - Position in repository
   - Tracked in workspace state
   - Used by `ls`, `cat`, `cd`, `pwd`
   - Persists across commands/sessions

## Configuration Files

### Profile Configuration

Individual JSON files: `~/.akashica/configurations/{profile}.json`

**Local storage**:
```json
{
  "version": "1.0",
  "name": "nas-video",
  "storage": {
    "type": "local",
    "path": "/Volumes/NAS/repos/video-campaign"
  },
  "created": "2025-10-08T10:30:00Z"
}
```

**S3 storage**:
```json
{
  "version": "1.0",
  "name": "s3-assets",
  "storage": {
    "type": "s3",
    "bucket": "my-bucket",
    "prefix": "repos/project-x",
    "region": "us-west-2"
  },
  "created": "2025-10-08T10:30:00Z"
}
```

**Notes**:
- No consolidated global config
- S3 credentials use AWS credential chain
- Profile name matches filename

### Workspace State

Per-profile state: `~/.akashica/workspaces/{profile}/state.json`

**Active workspace**:
```json
{
  "version": "1.0",
  "profile": "nas-video",
  "workspaceId": "@1045$ws_a3f2b8d9",
  "baseCommit": "@1045",
  "virtualCwd": "",
  "created": "2025-10-08T10:30:00Z",
  "lastUsed": "2025-10-08T14:22:00Z",
  "view": {
    "active": false,
    "commit": null
  }
}
```

**Note**: The root directory is stored as an empty string (`""`) in the state file but displayed as `/` to users. When reading state files, treat empty string as root path.

**View mode**:
```json
{
  "version": "1.0",
  "profile": "nas-video",
  "workspaceId": "@1045$ws_a3f2b8d9",
  "baseCommit": "@1045",
  "virtualCwd": "/docs/reports",
  "view": {
    "active": true,
    "commit": "@1032",
    "startedAt": "2025-10-08T15:00:00Z"
  }
}
```

**Critical behaviors**:
- One state file per profile
- Workspace ID in canonical format: `@commit$suffix`
- `virtualCwd` persists across commands
- View mode preserves workspace context
- Shell CWD never tracked

### Repository Metadata

Minimal marker: `{repository-root}/.akashica.json`

```json
{
  "version": "1.0",
  "repositoryId": "video-campaign",
  "created": "2025-10-08T10:00:00Z"
}
```

**Notes**:
- Repository format (sharding, hashing) implicit in version
- Version "1.0" = 2-level sharding, SHA256

## Command Context Resolution

`CommandContext` centralizes profile + workspace resolution.

**Resolution flow**:
```swift
static func resolve(profileFlag: String?) async throws -> CommandContext {
    // 1. Check --profile flag
    if let profile = profileFlag {
        return try await loadContext(profile: profile)
    }

    // 2. Check AKASHICA_PROFILE environment variable
    if let profile = ProcessInfo.processInfo.environment["AKASHICA_PROFILE"] {
        return try await loadContext(profile: profile)
    }

    // 3. Error - no profile specified
    throw ContextError.noProfile
}
```

**Provides**:
- Resolved profile configuration
- Current workspace state
- Storage adapter (local/S3)
- Repository actor
- Virtual CWD resolution
- Session creation

## aka:// URI Scheme

Explicit repository path scoping.

**Absolute paths** (start with `/`):
```bash
aka:/docs/file.pdf  # Always /docs/file.pdf
```

**Relative paths** (no leading `/`):
```bash
# If virtual CWD is /marketing:
aka:logo.png           # → /marketing/logo.png
aka:../docs/file.pdf   # → /docs/file.pdf
```

**Normalization**:
- Handles `.` and `..`
- Removes duplicate slashes
- Applied to both absolute and relative

## Storage Backends

### Storage Adapter Abstraction

```swift
protocol StorageAdapter {
    func readBranch(name: String) async throws -> BranchPointer
    func updateBranch(name: String, expectedCurrent: CommitID?, newCommit: CommitID) async throws
    func readRootManifest(commit: CommitID) async throws -> Data
    func writeRootManifest(commit: CommitID, data: Data) async throws
    func readObject(hash: String) async throws -> Data
    func writeObject(hash: String, data: Data) async throws
}
```

### Local Storage Adapter

Filesystem-based storage for NAS and local drives.

**Features**:
- File-based CAS for branch updates
- Atomic writes via rename
- 2-level directory sharding
- Direct filesystem access

### S3 Storage Adapter

AWS S3-based storage.

**Features**:
- AWS SDK for Swift
- AWS credential chain (environment vars, `~/.aws/credentials`, IAM roles)
- Conditional PUT for branch CAS (If-None-Match)
- Async/await throughout
- Multi-region support

**Credentials**:
- Never stored in Akashica configuration
- Uses standard AWS credential chain
- Same as AWS CLI

**Region configuration**:
```bash
$ akashica init --profile s3-assets s3://my-bucket/repos/project-x
AWS Region [us-east-1]: us-west-2
```

## Workflow Examples

### Initial Setup

**Create new repository (local)**:
```bash
$ akashica init --profile nas-video /Volumes/NAS/repos/video-campaign

Checking repository at /Volumes/NAS/repos/video-campaign...
✗ Repository not found

Create new repository? [Y/n]: Y

✓ Created repository
✓ Saved profile: ~/.akashica/configurations/nas-video.json
✓ Workspace state: ~/.akashica/workspaces/nas-video/state.json

To use this profile:
  export AKASHICA_PROFILE=nas-video
```

**Create new repository (S3)**:
```bash
$ akashica init --profile s3-assets s3://my-bucket/repos/project-x

Checking repository at s3://my-bucket/repos/project-x...
✗ Repository not found

AWS Region [us-east-1]: us-west-2

Create new repository? [Y/n]: Y

✓ Created repository
✓ Saved profile: ~/.akashica/configurations/s3-assets.json

To use this profile:
  export AKASHICA_PROFILE=s3-assets
```

**Attach to existing repository**:
```bash
$ akashica init --profile team-video /Volumes/NAS/repos/video-campaign

Checking repository at /Volumes/NAS/repos/video-campaign...
✓ Found existing repository: video-campaign

Attach to this repository? [Y/n]: Y

✓ Attached profile: team-video
✓ Saved profile: ~/.akashica/configurations/team-video.json

To use this profile:
  export AKASHICA_PROFILE=team-video

Run 'akashica checkout <branch>' to create a workspace.
```

### Daily Workflow

**Terminal session with profile**:
```bash
$ export AKASHICA_PROFILE=nas-video
$ cd ~/Desktop  # Can be anywhere

$ akashica checkout main
Created workspace @1045$ws_a3f2b8d9 from branch 'main'

$ akashica cd /videos
$ akashica cp ~/Desktop/intro.mp4 aka:intro.mp4
Staged: /videos/intro.mp4

$ akashica commit -m "Add intro video"
[main @1046] Add intro video

$ ls ~/Desktop
intro.mp4  # Shell directory unchanged, no .akashica/
```

**Multiple profiles in different terminals**:
```bash
# Terminal A - Video team
$ export AKASHICA_PROFILE=nas-video
$ akashica status
Nothing to commit, working tree clean

# Terminal B - Assets team
$ export AKASHICA_PROFILE=s3-assets
$ akashica status
Nothing to commit, working tree clean
```

**Shell independence**:
```bash
$ export AKASHICA_PROFILE=nas-video
$ cd ~/Desktop
$ akashica ls  # Works

$ cd /tmp
$ akashica ls  # Still works - same virtual CWD

$ cd /var/tmp
$ akashica commit -m "Update"  # Works from anywhere
```

### Profile Management

**List profiles**:
```bash
$ akashica profile list
Profiles:
  * nas-video (active, AKASHICA_PROFILE)
    Storage: /Volumes/NAS/repos/video-campaign (local)
    Workspace: @1045$ws_a3f2b8d9
    Virtual CWD: /videos

  s3-assets
    Storage: s3://my-bucket/repos/project-x
    Workspace: @2001$ws_7f8e9a0b
    Virtual CWD: /icons
```

**Show profile details**:
```bash
$ akashica profile show nas-video
Profile: nas-video

Storage:
  Type: local
  Path: /Volumes/NAS/repos/video-campaign

Configuration:
  File: ~/.akashica/configurations/nas-video.json
  Created: 2025-10-08 10:30:00

Workspace State:
  ID: @1045$ws_a3f2b8d9
  Base Commit: @1045
  Virtual CWD: /videos
  Last Used: 2025-10-08 14:22:00
```

**Delete profile**:
```bash
$ akashica profile delete s3-assets

Warning: This will delete profile configuration and workspace state.
Repository storage will NOT be deleted.

Delete profile? [y/N]: y

✓ Deleted profile: ~/.akashica/configurations/s3-assets.json
✓ Deleted workspace state: ~/.akashica/workspaces/s3-assets/
Repository preserved at: s3://my-bucket/repos/project-x
```

## Virtual Filesystem Operations

### Navigation

```bash
$ akashica checkout main
Created workspace @1$ws_a3f2

$ akashica pwd
/

$ akashica cd /docs
$ akashica pwd
/docs

$ akashica ls
manual.pdf  (2.4M)
guide.pdf   (1.8M)

$ akashica cat aka:manual.pdf | head -10
[PDF content...]
```

### Content Operations

**Upload (local → repository)**:
```bash
$ cd ~/Desktop
$ akashica cp video.mp4 aka:/videos/intro.mp4
Staged: /videos/intro.mp4
```

**Download (repository → local)**:
```bash
$ akashica cp aka:/videos/intro.mp4 ~/Desktop/intro-copy.mp4
Downloaded: ~/Desktop/intro-copy.mp4
```

**Delete**:
```bash
$ akashica rm aka:/videos/old.mp4
Deleted: /videos/old.mp4
```

**Move/rename**:
```bash
$ akashica mv aka:/old-name.txt aka:/new-name.txt
Moved: /old-name.txt → /new-name.txt
```

### View Mode

```bash
$ akashica view @1032
Entered read-only view mode at @1032
Virtual CWD: /

$ akashica ls aka:/docs/
manual-v1.pdf  (1.2M)

$ akashica cat aka:/docs/manual-v1.pdf
[Historical content...]

$ akashica cp ~/file.txt aka:/new.txt
Error: Cannot modify files in view mode

$ akashica view --exit
Exited view mode
```

## Multi-User Coordination

**No conflict resolution** needed:
- Workspaces are independent (private staging)
- Commits are immutable
- Branch updates atomic (Compare-And-Swap)

**Concurrent workflow**:
```bash
# User A
$ akashica cp ~/file.txt aka:/docs/file.txt
$ akashica commit -m "Add file"
[main @1046] Add file

# User B (different workspace)
$ akashica checkout main  # Gets @1046
$ akashica ls aka:/docs/
file.txt  (1.2K)  # Sees User A's change
```

**CAS conflict**:
```bash
# User A commits first
$ akashica commit -m "Update A"
[main @1046] Update A

# User B commits (branch moved)
$ akashica commit -m "Update B"
Error: Branch 'main' has moved
Run 'akashica checkout main' to get latest

$ akashica checkout main  # Get @1046
$ # Re-apply changes
$ akashica commit -m "Update B"
[main @1047] Update B
```

## Benefits

### Clean Working Directories

- Zero Akashica files in user directories
- Only user content
- No `.akashica/` pollution

### Multi-Repository Workflows

- Independent profiles per repository
- Switch contexts with environment variable
- Multiple profiles in different terminals

### Shell Independence

- Commands work from any directory
- No shell CWD coupling
- Safe by design (explicit staging)

### Storage Flexibility

- Local storage (NAS, local drives)
- S3 storage (cloud-native)
- Same commands for both
- Zero command changes to add new backend

### Simple Mental Model

- Profile = Repository config + Workspace
- Environment variable = Active profile
- Virtual CWD = Repository position
- Shell CWD = Local file I/O only
- Staging = Explicit actions only

## Implementation Components

### ProfileManager

Manages profile configuration files.

**Operations**:
- `profileExists(name:)` - Check if profile exists
- `loadProfile(name:)` - Load profile configuration
- `saveProfile(_:)` - Save profile configuration
- `listProfiles()` - List all profiles
- `deleteProfile(name:)` - Delete profile file

### WorkspaceStateManager

Manages workspace state files.

**Operations**:
- `loadState(profile:)` - Load workspace state
- `saveState(_:)` - Save workspace state
- `updateState(profile:update:)` - Atomic state update
- `deleteState(profile:)` - Delete workspace state

### ContextResolver

Resolves command execution context.

**Resolution**:
- Check `--profile` flag
- Check `AKASHICA_PROFILE` environment
- Error if neither specified

**Returns**:
- Profile configuration
- Workspace state
- Resolution source (flag/env)

### CommandContext

Centralized context for all commands.

**Provides**:
- Resolved profile
- Workspace state
- Storage adapter (local/S3)
- Repository actor
- Virtual CWD resolution
- Session creation (workspace/view)

**State management**:
- Update workspace state
- Update virtual CWD
- Enter/exit view mode

## References

- **AWS CLI Configuration**: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html
- **Getting Started Guide**: `docs/CLI_GETTING_STARTED.md`
- **User Guide**: `docs/CLI_USER_GUIDE.md`
- **Architecture Overview**: `docs/ARCHITECTURE.md`
