# Virtual Filesystem Quick Reference

**Version:** 1.0.0
**Status:** Production Ready (v0.10.0+)

## Overview

Akashica provides a virtual filesystem interface that lets you navigate and manage remote content stores (S3, NAS) as if they were local filesystems, without downloading everything to your local machine. This guide is a quick reference for the v0.10.0 profile-based architecture.

## Quick Start

```bash
# Initialize profile and repository
akashica init --profile my-project /Volumes/NAS/repos/my-project
# Or for S3:
# akashica init --profile my-project s3://my-bucket/repos/my-project

# Set active profile
export AKASHICA_PROFILE=my-project

# Create workspace from branch
akashica checkout main

# You're now in the virtual filesystem at /
akashica pwd
# Output: /

# Upload a file (use aka: prefix for repository paths)
akashica cp ~/photo.jpg aka:vacation.jpg

# List contents
akashica ls
# Output: vacation.jpg  (2.4M)

# Create nested structure
akashica cp ~/doc.pdf aka:/projects/2024/report.pdf

# Navigate
akashica cd /projects/2024
akashica pwd
# Output: /projects/2024

akashica ls
# Output: report.pdf  (450K)

# View file
akashica cat aka:report.pdf > /tmp/downloaded.pdf

# Download file
akashica cp aka:report.pdf ~/Desktop/

# Check changes
akashica status

# Commit changes
akashica commit -m "Add project files"
```

## Commands Reference

### Navigation & Inspection

| Command | Description | Example |
|---------|-------------|---------|
| `pwd` | Print virtual working directory | `akashica pwd` |
| `cd <path>` | Change virtual directory | `akashica cd /projects` |
| `ls [path]` | List directory contents | `akashica ls /projects` |
| `cat <path>` | Display file contents | `akashica cat readme.txt` |

### Content Operations

| Command | Description | Example |
|---------|-------------|---------|
| `cp <src> <dst>` | Copy file (upload/download) | `akashica cp ./file.pdf report.pdf` |
| `mv <src> <dst>` | Move/rename file | `akashica mv old.txt new.txt` |
| `rm <path>` | Delete file | `akashica rm unwanted.txt` |

### Version Control

| Command | Description | Example |
|---------|-------------|---------|
| `init --profile <name> <path>` | Initialize profile and repository | `akashica init --profile proj /path` |
| `checkout <branch>` | Create workspace from branch | `akashica checkout main` |
| `status` | Show workspace changes | `akashica status` |
| `commit -m "msg"` | Publish workspace to branch | `akashica commit -m "Update"` |
| `log` | Show commit history | `akashica log` |
| `branch` | List branches | `akashica branch` |

## aka:// URI Rules

**In v0.10.0, repository paths MUST use the `aka:` prefix** to distinguish them from local filesystem paths.

### Repository Paths (aka:// URIs)
- **Absolute**: `aka:/docs/file.pdf` - Always refers to `/docs/file.pdf`
- **Relative**: `aka:file.pdf` - Resolved from virtual CWD
- **Parent directory**: `aka:../other/file.pdf` - Relative navigation

### Local Paths (Your Computer)
- **Home directory**: `~/Desktop/file.txt`
- **Relative to shell CWD**: `./file.txt`, `../parent/file.txt`
- **Absolute local paths**: `/tmp/file.txt`, `/Users/name/file.txt`

### Examples

```bash
# ✅ Upload from local to remote (aka: prefix required)
akashica cp ~/photo.jpg aka:vacation.jpg
akashica cp ~/Desktop/report.pdf aka:/projects/report.pdf

# ✅ Download from remote to local (aka: prefix required)
akashica cp aka:vacation.jpg ~/Downloads/vacation.jpg
akashica cp aka:/projects/report.pdf ~/Desktop/

# ✅ Relative repository paths (from virtual CWD)
akashica cd /marketing
akashica cp ~/logo.png aka:logo.png  # → /marketing/logo.png
akashica cp aka:../docs/file.pdf ~/Desktop/  # → /docs/file.pdf

# ❌ Missing aka: prefix
akashica cp ~/file.txt vacation.jpg
# Error: Repository paths must use aka: prefix
```

## Path Navigation

Virtual paths work like shell paths:

```bash
# Absolute paths (from root)
akashica cd /japan/tokyo
akashica cp ./file.pdf /usa/california/file.pdf

# Relative paths (from current directory)
akashica cd japan
akashica cd tokyo
akashica cd ../osaka

# Path normalization
akashica cd /a/b/./c/../d
# Equivalent to: /a/b/d
```

## Workspace Model

**Key Concept:** Workspace = Staging Area

- `checkout` creates a **remote workspace** (in S3 or local storage)
- All changes (`cp`, `rm`, `mv`) modify the **remote workspace immediately**
- `commit` publishes the workspace as a new commit atomically
- No local staging directory needed (cloud-native workflow)

```bash
# Create workspace
akashica checkout main

# Make changes (all go to remote workspace)
akashica cp ./file1.txt file1.txt
akashica cp ./file2.txt file2.txt
akashica rm old-file.txt

# Review changes
akashica status

# Publish atomically
akashica commit -m "Update files"
# Workspace is now closed
```

## Profile-Based Configuration (v0.10.0)

### Creating Profiles

**Local storage (NAS)**:
```bash
akashica init --profile my-project /Volumes/NAS/repos/my-project
export AKASHICA_PROFILE=my-project
```

**S3 storage**:
```bash
akashica init --profile my-project s3://my-bucket/repos/my-project
# Prompts for AWS region interactively
export AKASHICA_PROFILE=my-project
```

### Profile Storage

Profiles stored in `~/.akashica/configurations/{profile}.json`:

**Local profile**:
```json
{
  "version": "1.0",
  "name": "my-project",
  "storage": {
    "type": "local",
    "path": "/Volumes/NAS/repos/my-project"
  },
  "created": "2025-10-08T10:30:00Z"
}
```

**S3 profile**:
```json
{
  "version": "1.0",
  "name": "my-project",
  "storage": {
    "type": "s3",
    "bucket": "my-bucket",
    "prefix": "repos/my-project",
    "region": "us-west-2"
  },
  "created": "2025-10-08T10:30:00Z"
}
```

### AWS Authentication

**S3 profiles use AWS credential chain** (no credentials stored in Akashica config):
- Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- `~/.aws/credentials` file
- IAM roles (for EC2/ECS)

**Region specified during init** (interactive prompt).

## Common Workflows

### Publishing Content

```bash
# Initialize repository and profile
akashica init --profile content-prod s3://content-prod/repos/photos
export AKASHICA_PROFILE=content-prod

# Create workspace
akashica checkout main

# Upload content (aka: prefix required)
akashica cd /2024/october
akashica cp ~/photos/sunset.jpg aka:sunset.jpg
akashica cp ~/photos/beach.jpg aka:beach.jpg

# Organize
akashica mv aka:sunset.jpg aka:../september/sunset.jpg

# Commit
akashica status
akashica commit -m "Add October photos"
```

### Managing Large Datasets

```bash
# Setup profile
export AKASHICA_PROFILE=weather-data

# Navigate virtual filesystem
akashica checkout main
akashica cd /datasets/weather/2024

# Add new data (uploads to remote workspace)
akashica cp ./october-data.csv aka:october.csv

# Review before committing
akashica ls
akashica cat aka:october.csv | head -10

# Commit changes
akashica commit -m "Add October weather data"
```

### Downloading Specific Files

```bash
# Setup profile
export AKASHICA_PROFILE=reports

# Checkout workspace
akashica checkout main

# Navigate to desired location
akashica cd /reports/2024

# Download specific files (aka: prefix required)
akashica cp aka:Q3-report.pdf ~/Downloads/
akashica cp aka:Q4-report.pdf ~/Downloads/

# No need to commit (no modifications made)
```

## Troubleshooting

### "Not in a workspace"

**Problem:** Trying to use virtual FS commands without a workspace.

**Solution:**
```bash
akashica checkout main
```

### "Both source and destination are local"

**Problem:** Trying to copy between two local paths.

**Solution:** Use regular `cp` command for local-to-local copies.

### "Repository paths must use aka: prefix"

**Problem:** Trying to use repository paths without `aka:` prefix.

**Solution:** Add `aka:` prefix to repository paths:
```bash
# ❌ Wrong
akashica cp ~/file.txt report.pdf

# ✅ Correct
akashica cp ~/file.txt aka:report.pdf
```

### "File not found"

**Problem:** Path doesn't exist in virtual filesystem.

**Solution:** Check current directory and use absolute aka: paths:
```bash
akashica pwd
akashica ls
akashica cat aka:/full/path/to/file.txt
```

## Performance Notes

### Local Storage
- All operations are fast (local disk I/O)
- No network latency

### S3 Storage
- **Read operations** (`ls`, `cat`): Network latency ~100-500ms
- **Write operations** (`cp`, `rm`, `mv`): Upload to S3 immediately
- **Optional caching** (post-MVP): Will cache reads locally

**Recommendation for large files:**
- Start with PDFs and images (< 100MB)
- Defer large video files until caching is implemented

## Differences from Git

| Aspect | Git | Akashica Virtual FS |
|--------|-----|---------------------|
| **Content location** | Clone entire repo locally | Content stays remote |
| **Working directory** | Full copy of files | Thin config + workspace tracking |
| **File access** | Direct filesystem access | Virtual paths, stream on-demand |
| **Scale** | Limited by local disk | Petabyte-scale remote storage |
| **Checkout** | Downloads all files | Creates remote workspace (no download) |
| **Staging** | Local staging area | Remote workspace in S3 |

## Next Steps

- Read the comprehensive guide: `docs/VIRTUAL_FILESYSTEM_GUIDE.md`
- Learn about profile-based architecture: `docs/PROFILE_ARCHITECTURE.md`
- Try with S3: Configure credentials and test with real bucket
- Report issues: https://github.com/anthropics/akashica/issues

---

**Built with** [Claude Code](https://claude.com/claude-code)
