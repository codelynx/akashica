# Virtual Filesystem Quick Reference

**Version:** 0.1.0
**Status:** Production Ready (Local), Ready for S3 Testing

## Overview

Akashica provides a virtual filesystem interface that lets you navigate and manage remote content stores (S3, NAS) as if they were local filesystems, without downloading everything to your local machine.

## Quick Start

```bash
# Initialize repository
akashica init

# Create workspace from branch
akashica checkout main

# You're now in the virtual filesystem at /
akashica pwd
# Output: /

# Upload a file
akashica cp ~/photo.jpg vacation.jpg

# List contents
akashica ls
# Output: vacation.jpg  (2.4M)

# Create nested structure
akashica cp ~/doc.pdf /projects/2024/report.pdf

# Navigate
akashica cd /projects/2024
akashica pwd
# Output: projects/2024

akashica ls
# Output: report.pdf  (450K)

# View file
akashica cat report.pdf > /tmp/downloaded.pdf

# Download file
akashica cp report.pdf ~/Desktop/

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
| `init` | Initialize repository | `akashica init` |
| `checkout <branch>` | Create workspace from branch | `akashica checkout main` |
| `status` | Show workspace changes | `akashica status` |
| `commit -m "msg"` | Publish workspace to branch | `akashica commit -m "Update"` |
| `log` | Show commit history | `akashica log` |
| `branch` | List branches | `akashica branch` |

## Path Detection Rules

The `cp` command automatically detects local vs remote paths:

### Remote Paths (Virtual Filesystem)
- **Bare names**: `banana.txt`
- **Paths with slashes**: `foo/bar.txt`, `dir/file.pdf`
- **Absolute repo paths**: `/japan/tokyo/file.txt`
- **Explicit prefix**: `remote:/path/to/file`

### Local Paths (Your Computer)
- **Home directory**: `~/Desktop/file.txt`
- **Relative to local dir**: `./file.txt`, `../parent/file.txt`
- **Explicit prefix**: `local:/tmp/file.txt`

### Examples

```bash
# ✅ Upload from local to remote
akashica cp ./photo.jpg vacation.jpg
akashica cp ~/Desktop/report.pdf /projects/report.pdf

# ✅ Download from remote to local
akashica cp vacation.jpg ./downloaded.jpg
akashica cp /projects/report.pdf ~/Desktop/

# ✅ Explicit prefixes (when ambiguous)
akashica cp local:/tmp/file.txt remote:/docs/file.txt

# ⚠️ Absolute paths are REMOTE by default
akashica cp report.pdf /tmp/out.pdf
# Error: remote-to-remote not supported
# This fails because /tmp/out.pdf is treated as a repository path!

# ✅ Use local: prefix for absolute local paths
akashica cp report.pdf local:/tmp/out.pdf
# Now /tmp/out.pdf is correctly recognized as your local filesystem
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

## S3 Configuration

### Option 1: Command-line flags (Quick testing)

```bash
akashica init --s3-bucket my-bucket --s3-region us-west-2
akashica checkout --s3-bucket my-bucket main
akashica cp ./file.txt doc.txt --s3-bucket my-bucket
```

### Option 2: Config file (Recommended)

Create `.akashica/config.json`:

```json
{
  "storage": {
    "type": "s3",
    "bucket": "my-content-bucket",
    "region": "us-west-2",
    "prefix": "projects/",
    "credentials": {
      "mode": "chain"
    }
  },
  "ui": {
    "color": true,
    "progress": true
  }
}
```

Then use commands without flags:
```bash
akashica checkout main
akashica cp ./file.txt doc.txt
```

### Authentication

**Recommended:** Use AWS credential chain
- Environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- `~/.aws/credentials` file
- IAM roles (for EC2/ECS)

**Alternative:** Static keys in config (NOT recommended for production)
```json
{
  "storage": {
    "credentials": {
      "mode": "static",
      "access_key_id": "AKIAIOSFODNN7EXAMPLE",
      "secret_access_key": "wJalr..."
    }
  }
}
```

**Security:** Add `.akashica/config.json` to `.gitignore` if it contains credentials.

## Common Workflows

### Publishing Content

```bash
# Initialize repository
akashica init --s3-bucket content-prod --s3-region us-west-2

# Create workspace
akashica checkout main

# Upload content
akashica cd /2024/october
akashica cp ~/photos/sunset.jpg sunset.jpg
akashica cp ~/photos/beach.jpg beach.jpg

# Organize
akashica mv sunset.jpg ../september/sunset.jpg

# Commit
akashica status
akashica commit -m "Add October photos"
```

### Managing Large Datasets

```bash
# Navigate virtual filesystem
akashica checkout main
akashica cd /datasets/weather/2024

# Add new data (uploads to S3 immediately)
akashica cp ./october-data.csv october.csv

# Review before committing
akashica ls
akashica cat october.csv | head -10

# Commit changes
akashica commit -m "Add October weather data"
```

### Downloading Specific Files

```bash
# Checkout read-only view
akashica checkout main

# Navigate to desired location
akashica cd /reports/2024

# Download specific files
akashica cp Q3-report.pdf ~/Downloads/
akashica cp Q4-report.pdf ~/Downloads/

# No need to commit (read-only)
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

### "Remote-to-remote copy not yet supported"

**Problem:** Absolute paths like `/tmp/file` are treated as remote.

**Solution:** Use `local:` prefix:
```bash
akashica cp report.pdf local:/tmp/report.pdf
```

### "File not found"

**Problem:** Path doesn't exist in virtual filesystem.

**Solution:** Check current directory and use absolute paths:
```bash
akashica pwd
akashica ls
akashica cat /full/path/to/file.txt
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

- Read the full design: `docs/plans/virtual-filesystem-ux.md`
- Try with S3: Configure credentials and test with real bucket
- Report issues: https://github.com/anthropics/akashica/issues

---

**Built with** [Claude Code](https://claude.com/claude-code)
