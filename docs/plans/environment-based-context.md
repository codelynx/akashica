# Environment-Based Context for Akashica

**Status**: Draft
**Version**: 0.10.0
**Date**: 2025-10-08
**Author**: Architecture Planning

## Overview

Pure environment-based architecture inspired by AWS CLI where:

1. **Working directories NEVER contain Akashica metadata** - Stay completely clean
2. **No backward compatibility concerns** - We're pre-v1.0.0, clean slate design
3. **Profile-based context** via environment variables (`AKASHICA_PROFILE`)
4. **Global configuration** in `~/.akashica/config.json`
5. **Repository storage** separate from working directories (NAS/S3/local)

## Core Problem

**Current v0.9.0 behavior** (unacceptable):
```
~/projects/my-work/
├── .akashica/           # Pollutes working directory
├── objects/             # Pollutes working directory
├── branches/            # Pollutes working directory
├── changeset/           # Pollutes working directory
└── myfile.txt           # User content
```

**Desired v0.10.0 behavior**:
```
~/projects/my-work/
└── myfile.txt           # ONLY user content - CLEAN!

~/.akashica/
└── config.json          # Global profile configuration

/Volumes/NAS/repos/video-campaign/
├── .akashica.json       # Repository metadata
├── objects/
├── branches/
└── changeset/
```

## Architecture

### Directory Structure

```
# Working directory - NO Akashica files
~/projects/my-work/
└── myfile.txt           # User content only (shell CWD lives here)

# Global Akashica configuration
~/.akashica/
└── configurations/
    ├── nas-video.json   # Individual profile config
    ├── s3-assets.json   # Individual profile config
    └── local-dev.json   # Individual profile config

# Repository storage (NAS)
/Volumes/NAS/repos/video-campaign/
├── .akashica.json       # Repository metadata
├── objects/
│   └── a3/f2/hash.dat
├── branches/
│   └── main.json
└── changeset/
    └── @1001/
        ├── commit.json
        └── .dir

# Repository storage (S3)
s3://my-bucket/repos/project-x/
├── .akashica.json
├── objects/
├── branches/
└── changeset/
```

### Profile Configuration

Each profile is stored as an individual JSON file in `~/.akashica/configurations/`.

**`~/.akashica/configurations/nas-video.json`**:
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

**`~/.akashica/configurations/s3-assets.json`**:
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

**`~/.akashica/configurations/local-dev.json`**:
```json
{
  "version": "1.0",
  "name": "local-dev",
  "storage": {
    "type": "local",
    "path": "~/Library/Akashica/repos/dev"
  },
  "created": "2025-10-08T11:45:00Z"
}
```

### Repository Metadata

**`/Volumes/NAS/repos/video-campaign/.akashica.json`**:
```json
{
  "version": "1.0",
  "repositoryId": "video-campaign",
  "created": "2025-10-08T10:00:00Z"
}
```

**Notes**:
- Repository format (sharding, hashing) is implicit in version number
- Version "1.0" = 2-level sharding, SHA256
- Future version "2.0" could introduce 3-level sharding if needed
- Workspace/runtime state is stored outside working directories (see below)

### Workspace State (CRITICAL)

**Problem**: CLI processes are stateless. Without persistent workspace state, commands can't track workspace ID, base commit, or active view mode.

**Solution**: Persist workspace state in profile-specific workspace directory.

**`~/.akashica/workspaces/{profile}/state.json`**:
```json
{
  "version": "1.0",
  "profile": "nas-video",
  "workspaceId": "@1045$ws_a3f2b8d9",
  "baseCommit": "@1045",
  "virtualCwd": "/",
  "created": "2025-10-08T10:30:00Z",
  "lastUsed": "2025-10-08T14:22:00Z",
  "view": {
    "active": false,
    "commit": null
  }
}
```

**When in view mode**:
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

**Key points**:
- One workspace state file per profile
- Tracks workspace ID in canonical format (@commit$suffix)
- **`virtualCwd`**: Current position in repository virtual filesystem
- **No shell CWD binding**: Shell location is user's business, not tracked
- Persists view mode state across commands
- Updated on every command execution

### Dual Path Model (Shell vs. Repository)

To keep Akashica commands free from directory-bound assumptions, every invocation resolves two
locations:

1. **Shell CWD** – The actual filesystem directory where the process runs. Used when commands read
   or write local files (e.g., `cp hello.txt aka:/docs/hello.txt`).
2. **Repository Virtual CWD** – The in-repository path tracked in the workspace state (e.g.,
   `/docs/reports`). Commands such as `akashica ls`, `akashica cat`, and `akashica cd` operate on
   this virtual path inside the selected workspace or view.

The runtime state captures the virtual CWD so follow-up commands can reconstruct repository context
regardless of where the shell is:

```json
{
  "profile": "nas-video",
  "workspaceId": "@1045$ws_a3f2b8d9",
  "baseCommit": "@1045",
  "virtualCwd": "/docs/reports",
  "view": {
    "active": false,
    "commit": null
  }
}
```

**Note**: Shell CWD is NOT tracked. Users have complete freedom to run commands from any directory.

**Implications**:
- `akashica commit` never scans the shell filesystem; it serialises staged mutations stored under
  `workspaceId`, guaranteeing clean commits regardless of where the shell CWD points.
- Entering view mode sets `view.active = true` and records `view.commit`, suspending writes while
  keeping the workspace context so `view --exit` can restore it instantly.
- `akashica cd` mutates `virtualCwd`; subsequent commands begin from that repository-relative path
  even across separate CLI processes.

## User Experience

### Initial Setup

#### Create New Repository (Local Storage)

```bash
$ akashica init --profile nas-video /Volumes/NAS/repos/video-campaign

Checking repository at /Volumes/NAS/repos/video-campaign...
✗ Repository not found

Create new repository? [Y/n]: Y

✓ Created repository at /Volumes/NAS/repos/video-campaign
✓ Saved profile: ~/.akashica/configurations/nas-video.json
✓ Workspace state: ~/.akashica/workspaces/nas-video/state.json

To use this profile:
  export AKASHICA_PROFILE=nas-video

You can now run akashica commands from any directory.
```

#### Create New Repository (S3 Storage)

```bash
# Initialize with S3 URI - storage type inferred from s3:// prefix
$ akashica init --profile s3-assets s3://my-bucket/repos/project-x

Checking repository at s3://my-bucket/repos/project-x...
✗ Repository not found

AWS Region [us-east-1]: us-west-2

Create new repository? [Y/n]: Y

✓ Created repository at s3://my-bucket/repos/project-x
✓ Saved profile: ~/.akashica/configurations/s3-assets.json

To use this profile:
  export AKASHICA_PROFILE=s3-assets
```

#### Attach to Existing Repository

```bash
$ akashica init --profile team-video /Volumes/NAS/repos/video-campaign

Checking repository at /Volumes/NAS/repos/video-campaign...
✓ Found existing repository: video-campaign

Available branches:
  * main (@1045)
    feature/intro (@1032)

Attach to this repository? [Y/n]: Y

✓ Attached profile: team-video
✓ Saved profile: ~/.akashica/configurations/team-video.json

To use this profile:
  export AKASHICA_PROFILE=team-video
```

### Daily Workflow

#### Terminal Sessions with Different Profiles

```bash
# Terminal A - Video editing team
$ export AKASHICA_PROFILE=nas-video
$ cd ~/Desktop  # Can be anywhere!
$ akashica status
Profile: nas-video
Repository: /Volumes/NAS/repos/video-campaign (local)
Workspace: @1045$ws_a3f2b8d9
Virtual CWD: /
Branch: main (@1045)

$ akashica cd /videos
$ akashica cp ~/Desktop/intro.mp4 aka:intro.mp4
Staged: /videos/intro.mp4
$ akashica commit -m "Add intro video"
✓ Committed @1046 to main
✓ Repository: /Volumes/NAS/repos/video-campaign

$ ls ~/Desktop
intro.mp4  # Shell directory unchanged, clean, no .akashica/!

# Terminal B - Asset management team (different profile)
$ export AKASHICA_PROFILE=s3-assets
$ cd /tmp  # Different profile, any shell location
$ akashica status
Profile: s3-assets
Repository: s3://my-bucket/repos/project-x
Workspace: @2001$ws_7f8e9a0b
Virtual CWD: /
Branch: main (@2001)

$ akashica cd /icons
$ akashica cp ~/Downloads/icon.png aka:new-icon.png
$ akashica commit -m "Update icons"
✓ Committed @2002 to main
✓ Repository: s3://my-bucket/repos/project-x

# Terminal C - Same profile, different shell location (WORKS)
$ export AKASHICA_PROFILE=nas-video
$ cd /var/tmp  # Completely different shell location
$ akashica status
Profile: nas-video
Repository: /Volumes/NAS/repos/video-campaign (local)
Workspace: @1045$ws_a3f2b8d9
Virtual CWD: /videos  # Preserved from Terminal A!
Branch: main (@1046)
```

**Key points**:
- Shell CWD is completely independent of Akashica context
- Multiple profiles = multiple independent workspaces
- Virtual CWD persists across commands and terminals
- Staging is explicit (via `cp`, `mv`, etc.), not filesystem scanning
- Commits only serialize staged mutations (safe by design)

#### Profile Selection

```bash
# Method 1: Environment variable (recommended for terminal sessions)
$ export AKASHICA_PROFILE=nas-video
$ akashica status
$ akashica commit -m "Update"

# Method 2: Command-line flag (one-off commands)
$ akashica --profile nas-video status
$ akashica --profile s3-assets commit -m "Update"
```

#### Shell Independence and Safety

```bash
$ export AKASHICA_PROFILE=nas-video

# Shell CWD can be ANYWHERE - it's irrelevant to Akashica
$ cd ~/Desktop
$ akashica status
Profile: nas-video
Workspace: @1045$ws_a3f2b8d9
Virtual CWD: /docs

$ cd /tmp
$ akashica ls
# Lists /docs contents (virtual CWD persisted)

$ cd ~/Downloads
$ akashica cp video.mp4 aka:/videos/intro.mp4
Staged: /videos/intro.mp4

$ cd /var/tmp
$ akashica commit -m "Add intro"
✓ Committed @1046 to main
# Only commits staged mutation, ignores shell filesystem
```

**Why this is safe**:
- `akashica commit` NEVER scans shell CWD
- Only staged mutations are committed (explicit user actions)
- Shell location is completely decoupled from repository operations
- No accidental commits possible - staging is always explicit

### Profile Management

#### List Profiles

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

  local-dev
    Storage: ~/Library/Akashica/repos/dev (local)
    Workspace: @1$ws_1a2b3c4d
    Virtual CWD: /
```

#### Show Profile Details

```bash
$ akashica profile show nas-video
Profile: nas-video
Storage:
  Type: local
  Path: /Volumes/NAS/repos/video-campaign
  Repository ID: video-campaign
  Format: 1.0
Workspace:
  ID: @1045$ws_a3f2b8d9
  Base Commit: @1045
  Virtual CWD: /videos
  Last Used: 2025-10-08 14:22:00
View Mode: inactive
Created: 2025-10-08 10:30:00
```

#### Delete Profile

```bash
$ akashica profile delete s3-assets

Warning: This will delete the profile configuration and workspace state.
Repository storage will NOT be deleted.

  Profile: s3-assets
  Storage: s3://my-bucket/repos/project-x
  Workspace: @2001$ws_7f8e9a0b

Delete profile? [y/N]: y

✓ Deleted profile: ~/.akashica/configurations/s3-assets.json
✓ Deleted workspace state: ~/.akashica/workspaces/s3-assets/state.json
Repository preserved at: s3://my-bucket/repos/project-x
```

### Context Resolution

When running any `akashica` command, context is resolved in this priority order:

1. **Command-line flag** `--profile` (highest priority)
   ```bash
   $ akashica --profile nas-video status
   ```

2. **Environment variable** `AKASHICA_PROFILE`
   ```bash
   $ export AKASHICA_PROFILE=nas-video
   $ akashica status
   ```

3. **Error if no context found** (no default profile)
   ```bash
   $ akashica status
   Error: No Akashica profile specified.

   Set active profile:
     $ export AKASHICA_PROFILE=<name>
     $ akashica --profile <name> status

   Or create a new profile:
     $ akashica init --profile <name> <storage-path>
   ```

## Configuration File Format

### Profile Configuration Files

Each profile is stored as an individual JSON file in `~/.akashica/configurations/`.

**`~/.akashica/configurations/nas-video.json`**:
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

**`~/.akashica/configurations/s3-assets.json`**:
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
- No consolidated global config file
- Each profile is independent
- Profile name matches filename (e.g., `nas-video.json` → profile "nas-video")
- Managed via `akashica init` and `akashica profile` commands

## Implementation Plan

### Phase 1: Core Profile System (v0.10.0)

**What needs to be built**:

1. **Profile Configuration Manager**
   - Load/save individual profile files from `~/.akashica/configurations/{name}.json`
   - List all available profiles
   - Delete profile files

2. **Workspace State Manager** (CRITICAL)
   - Load/save workspace state from `~/.akashica/workspaces/{profile}/state.json`
   - Track workspace ID, base commit, virtual CWD
   - Persist view mode state
   - Update `lastUsed` timestamp on every command
   - **No shell CWD tracking** - complete shell independence

3. **Context Resolver**
   - Check `--profile` flag (priority 1)
   - Check `AKASHICA_PROFILE` environment variable (priority 2)
   - Error if neither specified (no default profile)
   - Load workspace state to get virtual CWD and workspace ID
   - **No shell CWD validation** - commands work from any directory

4. **Repository Metadata**
   - Read/write `.akashica.json` in repository storage
   - Simple format: version, repositoryId, created date only
   - No format details (implicit in version number)

5. **Init Command Updates**
   - Can be run from any directory (shell CWD irrelevant)
   - Accept `--profile <name> <path>` arguments
   - Infer storage type from path (`s3://` vs local path)
   - Detect existing repository or create new one
   - Save profile configuration to `~/.akashica/configurations/{name}.json`
   - Create workspace state with virtual CWD = `/`

6. **Profile Management Commands**
   - `akashica profile list` - Show all profiles with workspace info
   - `akashica profile show <name>` - Show profile + workspace details
   - `akashica profile delete <name>` - Delete profile config + workspace state

7. **Update Existing Commands**
   - All commands resolve profile context (no shell CWD validation)
   - Load workspace state to get workspace ID, base commit, and virtual CWD
   - Commands operate on virtual filesystem using `virtualCwd` as base
   - Staging commands (`cp`, `mv`) read from shell CWD (explicit I/O)
   - Commit command only serializes staged mutations (never scans shell)
   - Update workspace state (virtual CWD, lastUsed) on successful operations

### Phase 2: Future Enhancements (v0.11.0+)

**Deferred for later**:
- Cache layer implementation
- Profile templates
- Shell integration
- Advanced management features

## Benefits

### Zero Working Directory Pollution
- Working directories contain ONLY user files
- No `.akashica/` anywhere in user's file tree
- Clean, predictable environment

### True Multi-Session Support
- Multiple terminals with independent contexts
- Same or different profiles per terminal
- No conflicts, no shared state

### Flexible Storage
- Repository storage on NAS, S3, or local drives
- Cache locally for performance (future)
- Shell CWD completely independent of repository context

### Simple Mental Model
- Profile = Repository config + Workspace state
- Environment variable = Active profile
- Virtual CWD tracks position in repository
- Shell CWD is irrelevant to Akashica operations
- No `.akashica/` in any directories
- Staging is explicit, commits are safe by design

## Migration from v0.9.0

**Not applicable** - We're pre-v1.0.0, no backward compatibility needed.

Users on v0.9.0 will need to:
1. Create new profiles via `akashica init`
2. Point to existing repository storage (if any)
3. Remove old `.akashica/` directories from working directories

## References

- AWS CLI configuration: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html
- Current design: `docs/design.md`
- Original separated storage proposal: `docs/plans/separated-storage-architecture.md`
