# Akashica CLI - Getting Started Guide

**A hands-on tutorial for web and PDF content publishers**

> **⚠️ DEVELOPMENT SOFTWARE - USE AT YOUR OWN RISK**
>
> Akashica is currently under active development and **NOT RECOMMENDED FOR PRODUCTION USE**. Always maintain separate backups of critical data.

---

## What You'll Build

In this tutorial, you'll set up a content repository for a fictional company **"TechPress"** that publishes technical documentation as PDFs and web content. You'll learn by doing:

1. Set up a content repository (S3 or NAS)
2. Create your first workspace
3. Add and version content files
4. Make changes and commit them
5. Discard unwanted changes
6. Review history and rewind to previous versions

**Time required**: 15-20 minutes

---

## Your Scenario

You're the **Technical Director** at TechPress. Your team publishes:
- Product documentation (PDFs)
- Marketing materials (images, PDFs)
- Website content (HTML, CSS, images)

You need a system to:
- Version all content (not just code)
- Work with multi-GB file sizes
- Store content on S3 (for distributed team access)
- Track "who changed what, when" for compliance

Let's build this step by step.

---

## Prerequisites

1. **Akashica installed**: `akashica --version` should work
2. **AWS credentials configured** (if using S3):
   ```bash
   # Check your AWS setup
   aws sts get-caller-identity
   ```
3. **Basic command line knowledge**: You're comfortable with terminal commands

---

## Part 1: Setting Up Your Repository

### Step 1: Prepare Your Storage

**Choose your storage backend:**

#### Option A: S3 (Recommended for teams)
```bash
# Create an S3 bucket (if you don't have one)
aws s3 mb s3://techpress-content --region us-west-2

# Verify it exists
aws s3 ls s3://techpress-content/
```

#### Option B: NAS/Local Storage
```bash
# Create a directory on your NAS
mkdir -p /Volumes/CompanyNAS/akashica-repos/techpress-content

# Or use local storage for testing
mkdir -p ~/akashica-storage/techpress-content
```

---

### Step 2: Initialize Your Profile

A **profile** connects Akashica to your storage backend. Think of it like configuring a Git remote.

#### For S3:
```bash
akashica init --profile techpress s3://techpress-content/repos/docs

# Output:
# Checking repository at s3://techpress-content/repos/docs...
# ✗ Repository not found
#
# AWS Region [us-east-1]: us-west-2
#
# Create new repository? [Y/n]: Y
#
# ✓ Created repository at s3://techpress-content/repos/docs
# ✓ Saved profile: ~/.akashica/configurations/techpress.json
# ✓ Workspace state: ~/.akashica/workspaces/techpress/state.json
#
# To use this profile:
#   export AKASHICA_PROFILE=techpress
```

#### For NAS/Local:
```bash
akashica init --profile techpress /Volumes/CompanyNAS/akashica-repos/techpress-content

# Output similar to S3, but no region prompt
```

**What just happened?**
- Akashica created a repository in your storage backend
- A profile named `techpress` was saved in `~/.akashica/configurations/`
- An empty workspace state was initialized

---

### Step 3: Activate Your Profile

```bash
# Set the active profile
export AKASHICA_PROFILE=techpress

# Add to your shell profile to make it permanent
echo 'export AKASHICA_PROFILE=techpress' >> ~/.bashrc  # or ~/.zshrc
```

**💡 Tip**: The `status` command requires an active workspace. You'll create one in the next step.

---

## Part 2: Your First Workspace

### Step 4: Create a Workspace

A **workspace** is your personal staging area for changes. Think of it as a draft you're working on.

```bash
# Create a workspace from the main branch
akashica checkout main

# Output:
# Created workspace @0$a3f2 from branch 'main'
# Base commit: @0
# Virtual CWD: /
```

**What just happened?**
- Akashica created an ephemeral workspace (ID: `@0$a3f2`)
- Your virtual working directory is set to `/` (root)
- You're now ready to add content

---

### Step 5: Add Your First File

Let's add a product manual PDF:

```bash
# Download or create a sample PDF (for this demo)
echo "TechPress Product Manual v1.0" > ~/Desktop/product-manual-v1.0.pdf

# Copy it to the repository
akashica cp ~/Desktop/product-manual-v1.0.pdf aka:/docs/product-manual.pdf

# Output:
# Staged: /docs/product-manual.pdf
```

**Understanding the aka:// URI:**
- `aka:/docs/product-manual.pdf` means "this file in my current workspace"
- The file is now staged (like `git add`)
- It's stored in your workspace, not yet committed

> **💡 aka: Path Rules**
>
> - **Absolute paths** start with `/`: `aka:/docs/file.pdf` → always refers to `/docs/file.pdf`
> - **Relative paths** don't start with `/`: `aka:file.pdf` → resolved from your virtual CWD
> - Examples:
>   - If your virtual CWD is `/marketing`:
>     - `aka:logo.png` → `/marketing/logo.png`
>     - `aka:/docs/manual.pdf` → `/docs/manual.pdf` (absolute, ignores CWD)

---

### Step 6: Check What Changed

```bash
akashica status

# Output:
# Added files:
#   + /docs/product-manual.pdf
```

---

### Step 7: Commit Your Changes

```bash
akashica commit -m "Add product manual v1.0"

# Output:
# [main @1] Add product manual v1.0
# Workspace published. New workspace: @1$b8e4
```

**What just happened?**
- Your changes were **published** to the `main` branch
- A new commit `@1` was created
- A fresh workspace (`@1$b8e4`) was created for your next changes
- The old workspace was deleted (changes are now permanent)

---

## Part 3: Making More Changes

### Step 8: Navigate and Add More Files

Let's add marketing materials:

```bash
# Navigate to the marketing folder (virtual navigation)
akashica cd /marketing

# Check where you are
akashica pwd
# Output: /marketing

# Add an image
akashica cp ~/Desktop/techpress-logo.png aka:logo.png

# Add a PDF brochure
akashica cp ~/Desktop/brochure-2024.pdf aka:brochure.pdf

# Check status
akashica status

# Output:
# Added files:
#   + /marketing/logo.png
#   + /marketing/brochure.pdf
```

**💡 Note**: `aka:logo.png` is relative to your current virtual CWD (`/marketing`)

---

### Step 9: List Files in Repository

```bash
# List files in current directory (virtual CWD)
akashica ls

# Output:
# logo.png  (15.2K)
# brochure.pdf  (2.4M)

# List files in root
akashica ls aka:/

# Output:
# docs/
# marketing/

# List docs folder
akashica ls aka:/docs/

# Output:
# product-manual.pdf  (1.8M)
```

---

### Step 10: View File Content

```bash
# View a text file
akashica cat aka:/docs/README.txt

# For binary files (PDFs, images), cat outputs raw bytes
# Use cp to download for viewing:
akashica cp aka:/marketing/logo.png ~/Desktop/logo-copy.png
```

---

## Part 4: Oops! Discarding Changes

### Step 11: Make a Mistake

```bash
# Accidentally add the wrong file
akashica cp ~/Desktop/personal-notes.txt aka:notes.txt

# Check status
akashica status

# Output:
# Added files:
#   + /marketing/logo.png
#   + /marketing/brochure.pdf
#   + /marketing/notes.txt  # ← Oops!
```

---

### Step 12: Discard All Changes

**Option A: Start fresh** (discard everything)

```bash
# Create a new workspace from main branch
akashica checkout main

# Output:
# Created workspace @1$c7d9 from branch 'main'
# Base commit: @1
# Virtual CWD: /
```

Your uncommitted changes are gone. The old workspace (`@1$b8e4`) is automatically deleted.

---

**Option B: Remove specific file** (before committing)

```bash
# Remove the wrong file
akashica rm aka:/marketing/notes.txt

# Check status
akashica status

# Output:
# Added files:
#   + /marketing/logo.png
#   + /marketing/brochure.pdf
# (notes.txt is gone)
```

---

### Step 13: Commit the Correct Changes

```bash
# Add the files again (if you did Option A)
akashica cp ~/Desktop/techpress-logo.png aka:/marketing/logo.png
akashica cp ~/Desktop/brochure-2024.pdf aka:/marketing/brochure.pdf

# Commit
akashica commit -m "Add marketing materials for 2024 campaign"

# Output:
# [main @2] Add marketing materials for 2024 campaign
# Workspace published. New workspace: @2$d3a1
```

---

## Part 5: Reviewing History

### Step 14: View Commit History

```bash
akashica log

# Output:
# @2 - Add marketing materials for 2024 campaign
#      Author: john.doe
#      Date: 2025-10-08 15:30:00
#
# @1 - Add product manual v1.0
#      Author: john.doe
#      Date: 2025-10-08 14:15:00
#
# @0 - Initial commit
#      Author: system
#      Date: 2025-10-08 14:00:00
```

---

### Step 15: View What Changed

Let's make a change and see the diff:

```bash
# Add a README file
echo "TechPress Documentation Repository" > ~/Desktop/README.txt
akashica cp ~/Desktop/README.txt aka:/README.txt

# See what changed in current workspace vs base commit
akashica diff

# Output:
# Added files:
#   /README.txt
#
# Modified files:
#   (none)
#
# Deleted files:
#   (none)

# Discard the change for now
akashica checkout main
```

**💡 Tip**: To see what changed in a previous commit, use view mode:
```bash
akashica view @1
akashica diff  # Shows changes between @0 and @1
akashica view --exit
```

---

## Part 6: Rewinding History (Branch Reset)

### Step 16: Oops! Wrong Commit

Let's say you committed the wrong files and want to undo the last commit:

```bash
# Check current state
akashica log
# Latest: @2 - Add marketing materials...

# Rewind the branch to previous commit
akashica branch reset main @1

# Output:
# Reset branch 'main' from @2 to @1

# Create new workspace from the reset branch
akashica checkout main

# Output:
# Created workspace @1$e4f7 from branch 'main'
# Base commit: @1
# Virtual CWD: /
```

**What just happened?**
- The `main` branch now points to `@1` (before the marketing materials)
- Commit `@2` is now orphaned (no longer reachable from any branch)
- You have a fresh workspace to redo the work correctly

---

### Step 17: Verify the Reset

```bash
akashica log

# Output:
# @1 - Add product manual v1.0
#      Author: john.doe
#      Date: 2025-10-08 14:15:00
#
# @0 - Initial commit
#      Author: system
#      Date: 2025-10-08 14:00:00
#
# (Commit @2 is gone from history)

akashica ls aka:/marketing/
# Output: (empty or error - marketing folder doesn't exist at @1)
```

---

## Part 7: View Mode (Read-Only Time Travel)

### Step 18: Inspect Historical Commits

Sometimes you want to look at old content without changing anything:

```bash
# Enter view mode at a specific commit
akashica view @1

# Output:
# Entered read-only view mode at @1
# Virtual CWD: /
#
# All commands now operate in this view context.
# To exit view mode: akashica view --exit

# Browse the content as it was at @1
akashica ls aka:/docs/
# Output: product-manual.pdf

akashica cat aka:/docs/product-manual.pdf
# (shows the content from @1)

# Try to make changes (will fail)
akashica cp ~/Desktop/new-file.txt aka:/new-file.txt
# Error: Cannot modify files in view mode
```

---

### Step 19: Exit View Mode

```bash
akashica view --exit

# Output:
# Exited view mode
#
# Run 'akashica checkout <branch>' to create a workspace
```

---

## Part 8: Working with Teams

### Step 20: Multiple Team Members

**Sarah (DevOps Engineer)** wants to work on the same repository:

```bash
# On Sarah's machine
akashica init --profile techpress s3://techpress-content/repos/docs

# Output:
# Checking repository at s3://techpress-content/repos/docs...
# ✓ Found existing repository: docs
#
# Attach to this repository? [Y/n]: Y
#
# ✓ Attached profile: techpress
# ✓ Saved profile: ~/.akashica/configurations/techpress.json

# Set active profile
export AKASHICA_PROFILE=techpress

# Create workspace
akashica checkout main

# Sarah now has her own workspace, independent of yours
# Workspace: @1$s4a8 (different from your @1$e4f7)
```

**Key points:**
- Each team member has their own workspace (private staging area)
- Workspaces don't conflict - they're independent
- Commits are atomic and linearized by the branch pointer

---

### Step 21: Sarah Makes Changes

```bash
# Sarah adds a file
akashica cp ~/Desktop/deployment-guide.pdf aka:/docs/deployment-guide.pdf

# Sarah commits
akashica commit -m "Add deployment guide"

# Output:
# [main @2] Add deployment guide
```

---

### Step 22: You See Sarah's Changes

```bash
# On your machine, create a new workspace to see latest
akashica checkout main

# Output:
# Exited workspace @1$e4f7
# Created workspace @2$f9b3 from branch 'main'
# Base commit: @2

# List files
akashica ls aka:/docs/

# Output:
# product-manual.pdf
# deployment-guide.pdf  # ← Sarah's file!
```

**No pull/merge needed** - just create a new workspace from `main` to see the latest.

---

## Summary: What You've Learned

✅ **Setup**: Initialize profiles for S3 or NAS storage
✅ **Workspaces**: Create personal staging areas for changes
✅ **Add Content**: Use `cp` to stage files with `aka://` URIs
✅ **Commit**: Publish changes to branches atomically
✅ **Discard**: Start fresh with `checkout` or remove specific files
✅ **History**: Review commits with `log` and `view`
✅ **Rewind**: Use `branch reset` to undo commits
✅ **Teams**: Independent workspaces, no merge conflicts

---

## Quick Reference Card

| Task | Command |
|------|---------|
| **Setup repository** | `akashica init --profile <name> <storage-path>` |
| **Set active profile** | `export AKASHICA_PROFILE=<name>` |
| **Create workspace** | `akashica checkout main` |
| **Add file** | `akashica cp <local> aka:<remote>` |
| **Remove file** | `akashica rm aka:<path>` |
| **Check status** | `akashica status` |
| **List files** | `akashica ls aka:<path>` |
| **View file** | `akashica cat aka:<path>` |
| **Navigate** | `akashica cd <path>` |
| **Commit changes** | `akashica commit -m "message"` |
| **View history** | `akashica log` |
| **Rewind branch** | `akashica branch reset <branch> <commit>` |
| **Time travel (read-only)** | `akashica view <commit>` |
| **Exit view mode** | `akashica view --exit` |

---

## Next Steps

Now that you understand the basics:

1. **Read the full user guide**: `docs/CLI_USER_GUIDE.md` - Covers advanced topics like branching, view mode, and best practices

2. **Explore the API**: If you're building integrations, see `docs/PROGRAMMING_GUIDE.md`

3. **Set up automation**: Consider scripting common workflows (e.g., nightly snapshots)

4. **Plan your storage**: Estimate costs for S3 (requests, storage, data transfer)

5. **Backup strategy**: While Akashica versions your content, maintain separate backups of critical data

---

## Common Questions

**Q: Where are my files stored?**
A: In your configured storage backend (S3 bucket or NAS directory). Your local machine only stores tiny config files in `~/.akashica/`.

**Q: Can I work offline?**
A: No. Akashica is designed for remote storage. Every operation needs network access to your storage backend.

**Q: What happens if two people commit at the same time?**
A: Akashica uses atomic Compare-And-Swap (CAS) operations. One commit succeeds, the other fails and needs to retry with `checkout main` to get the latest.

**Q: Can I delete old commits to save space?**
A: Not in v0.10.0. Content is immutable. Plan for growth or implement retention policies at the storage layer.

**Q: How do I handle large files (>5GB)?**
A: Works but may be slow. Future versions will add multipart uploads, progress indicators, and local caching.

**Q: What about credentials for S3?**
A: Akashica uses the standard AWS credential chain (environment variables, `~/.aws/credentials`, IAM roles). No credentials are stored in Akashica config files.

---

## Getting Help

- **Documentation**: `docs/` directory
- **Issues**: Report bugs at https://github.com/your-org/akashica/issues
- **Community**: (Add your support channels here)

---

**You're now ready to manage content at scale with Akashica!** 🎉
