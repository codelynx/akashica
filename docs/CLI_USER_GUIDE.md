# Akashica CLI User Guide

A comprehensive guide for technical directors and content management teams.

## Table of Contents

1. [Introduction](#introduction)
2. [What is Akashica?](#what-is-akashica)
3. [Getting Started](#getting-started)
4. [Storage Configuration](#storage-configuration)
5. [Understanding the Two-Tier Model](#understanding-the-two-tier-model)
6. [URI Scheme](#uri-scheme)
7. [Common Workflows](#common-workflows)
8. [Best Practices](#best-practices)
9. [Troubleshooting](#troubleshooting)
10. [FAQ](#faq)

---

## Introduction

This guide is designed for technical directors, content managers, and operations teams responsible for managing digital content at scale. Akashica provides Git-like version control specifically optimized for content management—whether you're managing marketing assets, documentation, media files, or configuration data.

**Who should read this guide:**
- Technical Directors overseeing content management systems
- DevOps engineers implementing content infrastructure
- Content operations teams managing digital assets
- System administrators deploying content repositories

**What you'll learn:**
- How to set up and configure Akashica for your organization
- How the two-tier workspace model enables safe, concurrent editing
- How to use the aka:// URI scheme for explicit content addressing
- Best practices for content workflows and team collaboration

---

## What is Akashica?

### Purpose

Akashica is a **content-addressed version control system** designed for managing files that change frequently but need complete history tracking. Unlike traditional file storage, Akashica:

- **Tracks every change**: Never lose a previous version
- **Deduplicates content**: Store identical files only once, regardless of path or filename
- **Enables concurrent editing**: Multiple team members can work simultaneously without conflicts
- **Supports multiple backends**: Use local storage for development, S3 for production
- **Provides explicit addressing**: Use URIs to reference exact versions (branches, commits, workspaces)

### Key Benefits for Content Management

**For Technical Directors:**
- **Cost efficiency**: Content deduplication reduces storage costs by 40-60% for typical content repositories
- **Audit compliance**: Complete change history with author, timestamp, and message for every modification
- **Disaster recovery**: Every commit is a complete snapshot—restore to any point in time
- **Scalability**: S3 backend handles petabytes of content with no infrastructure management

**For Content Teams:**
- **Safe experimentation**: Workspaces allow editing without affecting production content
- **Easy rollback**: Revert to any previous version instantly
- **Version comparison**: See exactly what changed between any two versions
- **Collaboration**: Work on different workspaces simultaneously, merge when ready

**For Operations:**
- **Infrastructure flexibility**: Start with local storage, migrate to S3 when needed
- **Multi-tenancy**: Isolate multiple projects in a single S3 bucket with key prefixes
- **API access**: Programmatic access to all content via Swift library
- **Cloud-native**: First-class AWS S3 support with built-in pagination and CAS

### Use Cases

1. **Marketing Asset Management**
   - Track all versions of brand assets, templates, and creative files
   - Enable designers to work independently, review before publishing
   - Maintain compliance records for regulated industries

2. **Documentation Systems**
   - Version control for technical documentation, manuals, and guides
   - Multiple authors working on different sections simultaneously
   - Easy rollback when errors are discovered

3. **Configuration Management**
   - Track changes to configuration files across environments
   - Branch-based workflow: development → staging → production
   - Audit trail for compliance and troubleshooting

4. **Media Libraries**
   - Manage video, audio, and image assets with full version history
   - Deduplicate identical media files regardless of location
   - Access historical versions for republishing or archiving

---

## Getting Started

### Installation

**Prerequisites:**
- macOS 13+ or Linux
- Swift 5.9+ (if building from source)

**Option 1: Build from source**
```bash
git clone https://github.com/yourusername/akashica.git
cd akashica
swift build -c release
cp .build/release/akashica /usr/local/bin/
```

**Option 2: Download binary** *(when available)*
```bash
# Download latest release
curl -L https://github.com/yourusername/akashica/releases/latest/akashica -o /usr/local/bin/akashica
chmod +x /usr/local/bin/akashica
```

**Verify installation:**
```bash
akashica --version
```

### Quick Start: 5-Minute Tutorial

Let's create your first Akashica repository and make a commit:

```bash
# 1. Create a new directory and initialize repository
mkdir my-content
cd my-content
akashica init

# 2. Create a workspace from main branch
akashica checkout main

# 3. Add some content
echo "# Welcome" > README.md
akashica cp README.md aka:/README.md

# 4. Check status
akashica status
# Output: Added files: README.md

# 5. Commit changes
akashica commit -m "Initial content"

# 6. View history
akashica log
# Output: [main @1234] Initial content
```

Congratulations! You've created your first Akashica repository with versioned content.

### Working from Subdirectories

Like Git, Akashica automatically finds your repository root by searching for the `.akashica` directory in parent directories. This means you can run `akashica` commands from anywhere inside your repository:

```bash
# Initialize repository
cd /Users/alice/my-content
akashica init
akashica checkout main

# Create some nested directories
mkdir -p projects/tokyo
cd projects/tokyo

# Commands work from subdirectories
akashica status          # ✓ Works - finds .akashica in /Users/alice/my-content
akashica ls aka:/        # ✓ Works - uses virtual CWD
akashica pwd             # Shows virtual CWD, not filesystem path

# Even from deep nesting
cd deep/nested/path
akashica commit -m "Update"  # ✓ Still works
```

**How it works:**

1. **Filesystem CWD**: Where you are in your terminal (e.g., `/Users/alice/my-content/projects/tokyo`)
2. **Repository discovery**: Akashica searches upward for `.akashica` directory
3. **Working root**: The directory containing `.akashica` becomes the repository root
4. **Virtual CWD**: Your logical position in the content tree (stored in `.akashica/CWD`)

**Benefits:**

- Run commands from any subdirectory (Git-like ergonomics)
- Prevents accidental nested repositories (init checks parent directories first)
- Better error messages ("Not in an Akashica repository")
- IDE and tool integration (editors can invoke Akashica from project subdirectories)

**Example:**

```bash
$ cd /Users/alice/my-content/scripts/deployment
$ akashica pwd
projects/tokyo
# ↑ Virtual CWD (logical position in content tree)

$ pwd
/Users/alice/my-content/scripts/deployment
# ↑ Filesystem CWD (where you are in terminal)
```

The filesystem location where you run the command is irrelevant—Akashica always finds the repository root and uses the virtual CWD for path resolution.

---

## Storage Configuration

Akashica supports two storage backends: **local filesystem** (for development/testing) and **AWS S3** (for production).

### Interactive Setup (Recommended)

When you run `akashica init` without any flags, you'll be prompted to configure storage interactively:

```bash
$ akashica init
Configure storage for your Akashica repository:

Storage type:
  1) Local filesystem (current directory)
  2) AWS S3 (cloud storage)

Enter choice [1-2]: 1

Initialized empty Akashica repository in /Users/alice/my-content/.akashica
Created branch 'main' at @0
```

**Configuration is saved** to `.akashica/config.json` - you never need to specify storage options again:

```json
{
  "storage": {
    "type": "local"
  }
}
```

**All future commands automatically use the saved configuration:**
```bash
$ akashica checkout main    # Uses local storage from config
$ akashica status           # Uses local storage from config
```

**Already initialized?** Running `akashica init` again will be rejected:
```bash
$ akashica init
Error: Repository already initialized at /Users/alice/my-content/.akashica
```

### Local Storage

**Best for:**
- Development and testing
- Small teams with shared network storage
- Air-gapped or on-premises deployments

**Interactive setup:**

```bash
$ akashica init
Storage type:
  1) Local filesystem (current directory)
> 1

Initialized empty Akashica repository in .akashica
Created branch 'main' at @0

# This creates .akashica/ directory containing:
# - objects/      : Content-addressed file storage
# - manifests/    : Directory structures
# - commits/      : Commit metadata
# - branches/     : Branch pointers
# - workspaces/   : Active editing sessions
# - config.json   : Storage configuration
```

**Non-interactive setup (automation):**

```bash
# Explicitly use local storage
akashica init --repo /path/to/repository
```

**Storage location:**
```
/my-content/
├── .akashica/           # Repository data (version controlled)
│   ├── objects/
│   ├── manifests/
│   ├── commits/
│   ├── branches/
│   └── workspaces/
└── [your working files]  # Not tracked by Akashica
```

**Multi-user setup** (shared NAS):
```bash
# On shared network storage
cd /mnt/nas/shared-content
akashica init

# All team members access the same repository
# Each user runs: akashica checkout main
# Each gets their own isolated workspace
```

### AWS S3 Storage

**Best for:**
- Production deployments
- Distributed teams
- Large-scale content libraries (terabytes to petabytes)
- Cloud-native architectures

**Setup:**

**Step 1: Create S3 bucket**
```bash
aws s3 mb s3://my-content-repo --region us-east-1
```

**Step 2: Configure IAM permissions**

Create an IAM policy with these minimum permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-content-repo",
        "arn:aws:s3:::my-content-repo/*"
      ]
    }
  ]
}
```

**Step 3: Initialize Akashica repository**

**Interactive setup (recommended):**
```bash
# IMPORTANT: Set AWS credentials BEFORE running init
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key

# Run interactive init
$ akashica init
Storage type:
  1) Local filesystem (current directory)
  2) AWS S3 (cloud storage)
> 2

S3 bucket name: my-content-repo
AWS region [us-east-1]: us-west-2
S3 key prefix (optional, press Enter to skip):

Initialized empty Akashica repository in S3 bucket 'my-content-repo'
  Region: us-west-2
Created branch 'main' at @0
```

**If initialization fails:**
```bash
Error: Failed to initialize S3 repository

Ensure:
  - S3 bucket 'my-content-repo' exists and is accessible
  - AWS credentials are valid
  - IAM permissions allow s3:PutObject and s3:ListBucket

You can retry 'akashica init' after fixing the issue.
```

Common solutions:
- **Bucket doesn't exist**: `aws s3 mb s3://my-content-repo --region us-west-2`
- **Missing credentials**: Set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- **Wrong region**: Verify bucket region matches the one you specified

This saves configuration to `.akashica/config.json`:
```json
{
  "storage": {
    "type": "s3",
    "bucket": "my-content-repo",
    "region": "us-west-2"
  }
}
```

**Non-interactive setup (automation):**
```bash
# Explicitly specify S3 options
akashica init --s3-bucket my-content-repo --s3-region us-west-2
```

**Step 4: Verify setup**
```bash
akashica branch
# Output: main
```

### Multi-Tenant S3 Configuration

For organizations managing multiple projects in a single bucket:

```bash
# Project A
cd /work/project-a
akashica init --s3-bucket shared-bucket --s3-prefix project-a

# Project B
cd /work/project-b
akashica init --s3-bucket shared-bucket --s3-prefix project-b
```

**S3 layout:**
```
s3://shared-bucket/
├── project-a/
│   ├── objects/
│   ├── branches/
│   └── commits/
└── project-b/
    ├── objects/
    ├── branches/
    └── commits/
```

**Benefits:**
- Complete isolation between projects
- Centralized billing and management
- Shared AWS account and permissions
- Simplified backup and disaster recovery

### Storage Backend Comparison

| Feature | Local Storage | AWS S3 |
|---------|--------------|--------|
| **Setup complexity** | Simple | Moderate (requires AWS account) |
| **Cost** | Storage hardware | ~$0.023/GB/month |
| **Scalability** | Limited by disk | Unlimited |
| **Multi-user** | Requires shared filesystem | Native cloud access |
| **Disaster recovery** | Manual backups | S3 versioning + replication |
| **Performance** | Very fast (local disk) | Fast (network latency) |
| **Best for** | Development, small teams | Production, distributed teams |

---

## Understanding the Two-Tier Model

Akashica uses a **dual-tier architecture** that separates immutable history (commits) from mutable workspaces. This design enables safe concurrent editing while maintaining a clean version history.

### The Two Tiers

```
┌─────────────────────────────────────────┐
│         Tier 1: Commits                 │
│         (Immutable History)             │
│                                         │
│  @0 ← @1234 ← @2548 ← @4776            │
│   │     │       │       │               │
│   └─────┴───────┴───────┘               │
│      Complete snapshots                 │
│      Never modified                     │
│      Permanent record                   │
└─────────────────────────────────────────┘
                ↓
┌─────────────────────────────────────────┐
│         Tier 2: Workspaces              │
│         (Ephemeral Editing)             │
│                                         │
│  @4776$a1b2   @4776$c3d4   @4776$e5f6  │
│  (Alice)      (Bob)         (Carol)     │
│  editing...   editing...    editing...  │
│                                         │
│  Can be published → new commit          │
│  Or discarded → no history impact       │
└─────────────────────────────────────────┘
```

### Tier 1: Commits (Immutable)

**What are commits?**
- Permanent snapshots of your content at a specific point in time
- Identified by commit ID (e.g., `@1234`)
- Contain metadata: author, message, timestamp, parent commit
- **Never modified** - once created, commits are read-only forever

**Why immutable?**
- **Audit trail**: Prove exactly what existed at any point in time
- **Safe rollback**: Always return to a known-good state
- **Blame tracking**: See who made which changes and when
- **Compliance**: Meet regulatory requirements for change tracking

**Example commit:**
```
Commit: @4776
Author: alice@company.com
Date: 2025-10-07 14:23:15
Message: Update product images for Q4 campaign

Parent: @2548
Files:
  - images/product-hero.jpg
  - images/product-thumbnail.jpg
  - metadata/campaign-q4.json
```

### Tier 2: Workspaces (Mutable)

**What are workspaces?**
- Temporary editing environments based on a commit
- Identified by workspace ID (e.g., `@4776$a1b2`)
- Support full read/write operations
- Can be published (→ new commit) or discarded (→ no trace)

**Why mutable workspaces?**
- **Experimentation**: Try changes without affecting production
- **Concurrent editing**: Multiple people edit simultaneously
- **Review workflow**: Preview changes before committing
- **Easy cleanup**: Discard failed experiments without polluting history

**Workspace lifecycle:**
```
1. Create:  akashica checkout main
            → Creates workspace @4776$a1b2 from latest commit

2. Edit:    akashica cp file.jpg aka:/images/
            akashica rm aka:/old-file.txt
            (make changes...)

3. Review:  akashica status
            akashica diff
            (verify changes look correct)

4. Publish: akashica commit -m "Update images"
            → Creates new commit @5112
            → Workspace @4776$a1b2 is closed

   OR

4. Discard: akashica workspace delete @4776$a1b2
            → No commit created, changes lost
```

### Concurrent Editing Example

**Scenario**: Three team members working simultaneously

```bash
# Alice creates workspace to update images
alice$ akashica checkout main
# Created workspace @4776$a1b2

alice$ akashica cp new-logo.svg aka:/branding/logo.svg
alice$ akashica commit -m "Update company logo"
# [main @5112] Update company logo

# Meanwhile, Bob works on documentation
bob$ akashica checkout main
# Created workspace @4776$c3d4 (from same commit @4776)

bob$ akashica cp readme.md aka:/README.md
bob$ akashica commit -m "Add installation instructions"
# [main @5223] Add installation instructions

# Carol works on configuration
carol$ akashica checkout main
# Created workspace @5223$e5f6 (from Bob's commit)

carol$ akashica cp config.yml aka:/settings/
carol$ akashica commit -m "Update production config"
# [main @5445] Update production config
```

**Result**: Clean linear history
```
@0 → @4776 → @5112 → @5223 → @5445
             (Alice) (Bob)   (Carol)
```

**Key insight**: Each person worked independently. No merge conflicts because commits are sequential. Last-writer-wins for the branch pointer.

### Two-Tier Benefits

**For Content Teams:**
1. **Safe experimentation**: Edit freely, discard bad attempts
2. **No conflicts**: Each person has isolated workspace
3. **Preview before publish**: Review changes before committing
4. **Easy rollback**: Commits are immutable—always recoverable

**For Technical Directors:**
1. **Simplified workflow**: No complex merge algorithms
2. **Clear audit trail**: Commits show exactly who did what when
3. **Reduced errors**: Workspaces catch mistakes before they're permanent
4. **Compliance ready**: Immutable history meets regulatory requirements

**For Operations:**
1. **Predictable performance**: No merge computation overhead
2. **Easy cleanup**: Delete workspaces without affecting commits
3. **Simple backup**: Only commits need backing up
4. **Straightforward recovery**: Restore any commit instantly

---

## URI Scheme

Akashica uses an **explicit URI scheme** (`aka://`) to specify exactly which version of content you want to access. This eliminates ambiguity and enables powerful workflows.

### Why URIs?

**Before URIs** (traditional systems):
```bash
cat report.pdf
# Question: Which version? Current? Production? Last month's?
```

**With aka:// URIs**:
```bash
akashica cat aka:/report.pdf           # Current workspace
akashica cat aka:///report.pdf         # Workspace root
akashica cat aka://main/report.pdf     # Latest from main branch
akashica cat aka://@4776/report.pdf    # Specific commit
```

**Benefits:**
- **Explicit**: No guessing which version
- **Precise**: Reference exact commits or branches
- **Safe**: Clear distinction between read-only and writable scopes
- **Auditable**: URIs document intent in scripts and logs

### URI Formats

Three formats for different use cases:

#### 1. Relative Path (aka:/path)

**Format**: `aka:/path/to/file`

**Meaning**: Relative to current virtual working directory

**Use when**:
- Navigating within current workspace
- Working in a specific directory context
- Mirroring traditional command-line workflows

**Examples**:
```bash
# Start at root
$ akashica pwd
/

# Navigate into projects directory
$ akashica cd aka:/projects
$ akashica pwd
/projects

# List current directory (relative)
$ akashica ls
tokyo/

# Read file relative to current dir
$ akashica cat aka:/tokyo/data.json
{...}

# This reads /projects/tokyo/data.json
```

#### 2. Absolute Path (aka:///path)

**Format**: `aka:///path/to/file`

**Meaning**: Absolute path from repository root

**Use when**:
- Accessing files regardless of current directory
- Writing scripts that need consistent paths
- Avoiding ambiguity about location

**Examples**:
```bash
# Current directory doesn't matter
$ akashica pwd
/projects/tokyo

# Absolute path ignores CWD
$ akashica cat aka:///config/settings.yml
# Reads from /config/settings.yml

$ akashica ls aka:///
# Always lists repository root

$ akashica cp report.pdf aka:///archive/2025/q4-report.pdf
# Uploads to /archive/2025/ regardless of CWD
```

#### 3. Scoped Path (aka://scope/path)

**Format**: `aka://scope/path/to/file`

**Scopes**:
- **Branch name**: `aka://main/file.txt` (latest commit on branch)
- **Commit ID**: `aka://@1234/file.txt` (specific commit)

**Use when**:
- Reading from production (branch)
- Accessing historical versions (commit)
- Comparing versions across branches
- Auditing or compliance checks

**Examples**:
```bash
# Read latest from main branch
$ akashica cat aka://main/README.md

# Read from staging branch
$ akashica cat aka://staging/config.yml

# Read from specific commit (history)
$ akashica cat aka://@4776/images/old-logo.svg

# List directory in commit
$ akashica ls aka://@2548/reports/

# Download file from branch
$ akashica cp aka://main/template.html ./backup/
```

### Read-Only vs. Writable Scopes

**Read-only scopes** (cannot modify):
- Branches: `aka://main/`
- Commits: `aka://@1234/`

**Writable scopes** (can modify):
- Current workspace: `aka:/` or `aka:///`

**Examples of automatic validation**:
```bash
# ✅ Allowed: Write to workspace
$ akashica cp file.txt aka:/draft.txt
Uploaded file.txt → draft.txt

# ❌ Blocked: Write to branch
$ akashica cp file.txt aka://main/file.txt
Error: Cannot write to read-only scope: branch 'main'
Use aka:/ or aka:/// to write to the current workspace

# ✅ Allowed: Read from branch
$ akashica cat aka://main/file.txt
(file contents)

# ❌ Blocked: Delete from commit
$ akashica rm aka://@4776/old-file.txt
Error: Cannot delete from read-only scope: commit @4776
Only current workspace (aka:/ or aka:///) supports deletions
```

### Virtual Working Directory

Like traditional shells, Akashica maintains a **virtual current working directory** (CWD):

```bash
# Check current directory
$ akashica pwd
/

# Change directory
$ akashica cd aka:/projects/tokyo
projects/tokyo

# Relative operations use CWD
$ akashica ls
# Shows contents of /projects/tokyo/

$ akashica cat aka:/data.json
# Reads /projects/tokyo/data.json
```

**Important**: Virtual CWD is stored in `.akashica/CWD` and persists between commands.

### URI Examples by Use Case

**Content Manager daily workflow**:
```bash
# Start working day
akashica checkout main
akashica cd aka:/campaign/q4

# Upload new assets
akashica cp hero-image.jpg aka:/images/
akashica cp copy.txt aka:/content/

# Review changes
akashica status
akashica diff

# Publish
akashica commit -m "Add Q4 campaign assets"
```

**Compliance officer audit**:
```bash
# View file at specific date
akashica log | grep "2025-09-15"
# Found: commit @3456

# Read that version
akashica cat aka://@3456/financial/q3-report.pdf > archive/

# Compare with current
diff <(akashica cat aka://@3456/report.pdf) \
     <(akashica cat aka://main/report.pdf)
```

**Operations engineer deployment**:
```bash
# Download production config
akashica cp aka://main/prod-config.yml /etc/app/

# Download staging config (for comparison)
akashica cp aka://staging/staging-config.yml /tmp/

# Verify differences before deploying
diff /etc/app/prod-config.yml /tmp/staging-config.yml
```

**Developer testing historical version**:
```bash
# Find commit from 2 weeks ago
akashica log | grep "2025-09-23"
# Found: @2891

# Download old version
akashica cp aka://@2891/api-schema.json ./test-data/

# Run tests against old schema
npm test -- --schema=./test-data/api-schema.json
```

### URI Quick Reference

| Goal | URI Format | Example |
|------|-----------|---------|
| Access current workspace file | `aka:/path` | `aka:/draft.txt` |
| Access from repository root | `aka:///path` | `aka:///config/app.yml` |
| Read from branch | `aka://branch/path` | `aka://main/README.md` |
| Read from commit | `aka://@ID/path` | `aka://@4776/logo.svg` |
| List current directory | `aka:/` | `akashica ls aka:/` |
| List repository root | `aka:///` | `akashica ls aka:///` |
| Navigate to directory | `aka:/dir` | `akashica cd aka:/projects` |

---

## Common Workflows

### Workflow 1: Daily Content Updates

**Scenario**: Content manager updating marketing materials

```bash
# Morning: Start working
cd /work/marketing-content
akashica checkout main
akashica cd aka:/campaigns/2025-q4

# Add new hero image
akashica cp ~/Downloads/hero-v3.jpg aka:/images/hero.jpg

# Update copy
akashica cp ~/Documents/copy-final.txt aka:/content/headline.txt

# Review what changed
akashica status
# Output:
# Modified files:
#   images/hero.jpg
#   content/headline.txt

akashica diff
# Shows new content

# Publish changes
akashica commit -m "Update Q4 hero image and headline copy"

# Done! Changes are live
```

**Key points**:
- Start each day with `checkout main` to get a fresh workspace
- Use relative paths (`aka:/`) for convenience
- Always review with `status` and `diff` before committing
- Commit messages should describe "why", not "what"

### Workflow 2: Multi-Stage Review Process

**Scenario**: Content requires review before production

```bash
# Content creator: Create draft
akashica checkout main
akashica cp draft-article.md aka:/articles/new-product.md
akashica commit -m "Draft: New product announcement"

# Reviewer: Check out at specific commit for review
akashica log  # Note commit ID, e.g., @5234

# Download for review (external tool)
akashica cp aka://@5234/articles/new-product.md ~/review/

# After approval, editor makes final edits
akashica checkout main
akashica cp ~/review/new-product-edited.md aka:/articles/new-product.md
akashica commit -m "Final: New product announcement (reviewed)"

# Published!
```

**Key points**:
- Each stage creates a commit (audit trail)
- Use commit IDs to reference exact versions
- External tools can work with exported content
- History shows entire review process

### Workflow 3: Branch-Based Environment Promotion

**Scenario**: Configuration changes flow dev → staging → production

```bash
# Developer: Create change in development
cd /work/app-config
akashica checkout dev
akashica cp new-feature-config.yml aka:/features/feature-x.yml
akashica commit -m "Add feature X configuration"

# Promote to staging
akashica checkout staging
akashica cp aka://dev/features/feature-x.yml aka:/features/
akashica commit -m "Promote feature X config to staging"

# After testing, promote to production
akashica checkout main
akashica cp aka://staging/features/feature-x.yml aka:/features/
akashica commit -m "Promote feature X config to production"
```

**Branch strategy**:
```
dev      →  staging  →  main (production)
(rapid)     (tested)     (stable)
```

**Key points**:
- Each environment has its own branch
- Use `aka://branch/` to copy between environments
- Explicit promotion steps (audit trail)
- Production (main) only receives tested changes

### Workflow 4: Hotfix Production Content

**Scenario**: Critical error in production needs immediate fix

```bash
# Discover issue in production
akashica cat aka://main/legal/terms.pdf
# ERROR: Outdated terms, wrong date

# Create workspace from production
akashica checkout main

# Fix the issue
akashica cp ~/fixed-terms.pdf aka:/legal/terms.pdf

# Verify fix
akashica diff aka:/legal/terms.pdf

# Publish immediately
akashica commit -m "HOTFIX: Update legal terms with correct date"

# Verify production updated
akashica cat aka://main/legal/terms.pdf
# Correct!
```

**For emergency rollback**:
```bash
# Check recent history
akashica log | head -5
# @6789 - HOTFIX: Update terms... (broken)
# @6723 - Update pricing... (good)

# Rollback: checkout previous good commit
akashica checkout @6723
akashica cat aka:/legal/terms.pdf  # Verify it's good

# Publish the rollback
akashica commit -m "Rollback broken terms update"
```

**Key points**:
- Hotfixes use same workflow as normal changes
- Commit messages should indicate urgency (e.g., "HOTFIX")
- Rollback is just creating new commit from old content
- History preserves both the break and the fix

### Workflow 5: Archiving and Compliance

**Scenario**: Quarterly archive for compliance audit

```bash
# End of Q4 2025: Create archive
akashica log --since="2025-10-01" --until="2025-12-31"
# Find all Q4 commits

# Download final state
mkdir ~/archives/2025-q4
cd ~/archives/2025-q4

# Get latest commit of Q4
akashica log | grep "2025-12-31" | head -1
# @8912 - Final Q4 update

# Archive entire repository state
akashica cp aka://@8912/. ./ --recursive

# Create manifest
akashica log --since="2025-10-01" --until="2025-12-31" > CHANGELOG-Q4.txt

# Compress for archival
tar -czf ../akashica-2025-q4.tar.gz .
```

**For audit retrieval** (6 months later):
```bash
# Auditor: "Show me the hero image from 2025-11-15"
akashica log | grep "2025-11-15"
# @7234 - Update hero image for holiday campaign

akashica cp aka://@7234/images/hero.jpg ~/audit-evidence/hero-2025-11-15.jpg

# Prove authenticity
akashica log --show=@7234
# Output:
# Commit: @7234
# Author: alice@company.com
# Date: 2025-11-15 14:23:45
# Message: Update hero image for holiday campaign
# Hash: SHA256:a1b2c3d4...
```

**Key points**:
- Commits provide immutable evidence for audits
- Use commit IDs to reference exact historical state
- Export full repository state at key dates
- Hashes prove content hasn't been tampered with

---

## Best Practices

### For Content Teams

**1. Commit often, commit meaningfully**
```bash
# ❌ Bad: Vague message
akashica commit -m "updates"

# ✅ Good: Descriptive message
akashica commit -m "Update product pricing for 2025 catalog"
```

**2. Use descriptive branch names**
```bash
# ❌ Bad: Generic names
main, test, staging

# ✅ Good: Clear purpose
main (production)
staging (pre-release testing)
dev (active development)
campaign-q1-2026 (specific initiative)
```

**3. Review before committing**
```bash
# Always run these before commit:
akashica status    # What files changed?
akashica diff      # What are the changes?

# Then commit with confidence
akashica commit -m "..."
```

**4. Don't commit sensitive data**
```bash
# ❌ Never commit:
- API keys or passwords
- Personal customer data (without encryption)
- Internal financial data (unless authorized)

# Use .akashica/ignore (if implemented)
secrets/
*.key
credentials.json
```

### For Technical Directors

**1. Establish clear branch strategy**

**Example strategy**:
```
main          → Production (customer-facing)
staging       → Pre-release testing
dev           → Active development
feature/*     → Specific features/campaigns
hotfix/*      → Emergency production fixes
```

**2. Set up automated backups**
```bash
# Daily backup script
#!/bin/bash
DATE=$(date +%Y-%m-%d)
akashica log -n 1 > backup-$DATE.log
aws s3 sync s3://my-content-repo s3://backup-bucket/daily/$DATE/
```

**3. Monitor repository growth**
```bash
# Check storage size monthly
aws s3 ls s3://my-content-repo --recursive --summarize

# Identify large files
akashica ls aka:/// --recursive | sort -k2 -hr | head -20
```

**4. Document workflows**
```markdown
# team-workflows.md

## Content Publishing Workflow
1. Create workspace: `akashica checkout main`
2. Make changes: `akashica cp ...`
3. Review: `akashica status && akashica diff`
4. Commit: `akashica commit -m "..."`
5. Verify: `akashica cat aka://main/...`

## Emergency Rollback
1. Find last good commit: `akashica log`
2. Create workspace: `akashica checkout @XXXX`
3. Publish: `akashica commit -m "Rollback: ..."`
```

### For Operations Teams

**1. Use infrastructure as code**
```hcl
# Terraform example
resource "aws_s3_bucket" "content_repo" {
  bucket = "company-content-repo"
  versioning {
    enabled = true  # S3 versioning as backup
  }
  lifecycle_rule {
    enabled = true
    noncurrent_version_expiration {
      days = 90  # Clean up old S3 versions
    }
  }
}
```

**2. Set up monitoring and alerting**
```bash
# CloudWatch metric: Repository size
aws cloudwatch put-metric-data \
  --namespace Akashica \
  --metric-name RepositorySize \
  --value $(aws s3 ls s3://my-repo --summarize | grep "Total Size" | awk '{print $3}')

# Alert if size grows >10% in one day
```

**3. Implement least-privilege access**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT:role/ContentEditor"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::my-repo/content/*"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ACCOUNT:role/ContentAdmin"
      },
      "Action": "s3:*",
      "Resource": "arn:aws:s3:::my-repo/*"
    }
  ]
}
```

**4. Test disaster recovery**
```bash
# Quarterly DR drill
# 1. Create test restore environment
mkdir /tmp/dr-test
cd /tmp/dr-test

# 2. Initialize from backup
akashica init --s3-bucket backup-bucket --s3-prefix restore-test/

# 3. Verify data integrity
akashica log | head -10
akashica cat aka://main/critical-file.pdf

# 4. Measure recovery time (RTO)
```

### Security Best Practices

**1. Use AWS IAM roles (not access keys)**
```bash
# ✅ Good: Use IAM role (ECS, EC2, Lambda)
# AWS SDK automatically uses instance profile

# ❌ Bad: Hardcoded credentials
export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
```

**2. Enable S3 bucket versioning**
```bash
aws s3api put-bucket-versioning \
  --bucket my-content-repo \
  --versioning-configuration Status=Enabled

# Protects against accidental deletion
# Allows recovery from data corruption
```

**3. Encrypt sensitive content**
```bash
# Before uploading sensitive files
openssl enc -aes-256-cbc -in sensitive.pdf -out sensitive.pdf.enc
akashica cp sensitive.pdf.enc aka:/confidential/

# S3 server-side encryption
aws s3api put-bucket-encryption \
  --bucket my-content-repo \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

**4. Audit access logs**
```bash
# Enable S3 access logging
aws s3api put-bucket-logging \
  --bucket my-content-repo \
  --bucket-logging-status '{
    "LoggingEnabled": {
      "TargetBucket": "my-audit-logs",
      "TargetPrefix": "akashica-access/"
    }
  }'

# Review logs quarterly
aws s3 ls s3://my-audit-logs/akashica-access/2025/10/ | grep "REST.GET"
```

---

## Troubleshooting

### Common Issues

#### Issue 1: "No active workspace"

**Error**:
```bash
$ akashica cat aka:/file.txt
Error: No active workspace
Run 'akashica checkout <branch>' to create a workspace
```

**Cause**: No workspace created yet, or workspace was deleted

**Solution**:
```bash
akashica checkout main
```

---

#### Issue 2: "Cannot write to read-only scope"

**Error**:
```bash
$ akashica cp file.txt aka://main/file.txt
Error: Cannot write to read-only scope: branch 'main'
```

**Cause**: Attempting to write to a branch or commit (read-only)

**Solution**:
```bash
# Write to current workspace instead
akashica cp file.txt aka:/file.txt

# Then commit to update the branch
akashica commit -m "Add file"
```

---

#### Issue 3: "Branch not found"

**Error**:
```bash
$ akashica checkout production
Error: Branch 'production' not found
Use 'akashica branch' to see available branches
```

**Cause**: Branch doesn't exist

**Solution**:
```bash
# List available branches
akashica branch

# If branch should exist, check initialization
akashica init --s3-bucket ... # Re-initialize if needed
```

---

#### Issue 4: S3 permissions error

**Error**:
```bash
$ akashica init --s3-bucket my-bucket
Error: Access Denied (403)
```

**Cause**: AWS credentials don't have sufficient permissions

**Solution**:
```bash
# Check credentials
aws sts get-caller-identity

# Verify IAM policy includes:
# - s3:GetObject
# - s3:PutObject
# - s3:ListBucket

# Test bucket access
aws s3 ls s3://my-bucket
```

---

#### Issue 5: "File not found" after cd

**Error**:
```bash
$ akashica cd aka:/projects
$ akashica cat aka:/data.txt
Error: File not found: data.txt
```

**Cause**: Relative path is based on current directory

**Solution**:
```bash
# Check current directory
akashica pwd
# Output: /projects

# File is actually at /projects/tokyo/data.txt
akashica cat aka:/tokyo/data.txt

# Or use absolute path
akashica cat aka:///projects/tokyo/data.txt
```

---

### Performance Issues

#### Slow S3 operations

**Symptoms**: Upload/download takes minutes

**Diagnosis**:
```bash
# Check network latency
ping s3.us-east-1.amazonaws.com

# Check file size
ls -lh myfile.dat
```

**Solutions**:
1. **Use S3 Transfer Acceleration**:
```bash
aws s3api put-bucket-accelerate-configuration \
  --bucket my-content-repo \
  --accelerate-configuration Status=Enabled
```

2. **Choose region closer to users**:
```bash
# Migrate to closer region
aws s3 sync s3://us-east-1-bucket s3://eu-west-1-bucket
```

3. **Compress large files**:
```bash
# Before uploading
gzip large-video.mp4
akashica cp large-video.mp4.gz aka:/media/
```

---

#### Slow `ls` operations

**Symptoms**: Listing large directories takes long time

**Cause**: Many files in single directory (thousands)

**Solution**: Organize into subdirectories
```bash
# ❌ Bad: Flat structure
/images/
  image001.jpg
  image002.jpg
  ...
  image9999.jpg

# ✅ Good: Hierarchical structure
/images/
  2025/
    01/
      image001.jpg
      image002.jpg
    02/
      ...
```

---

### Getting Help

**Check command help**:
```bash
akashica --help
akashica <command> --help
```

**Enable verbose logging**:
```bash
# Set environment variable
export AKASHICA_LOG_LEVEL=debug
akashica commit -m "..."
```

**Report issues**:
- GitHub Issues: https://github.com/yourusername/akashica/issues
- Include: command run, error message, akashica version
- Attach: debug logs (with sensitive data redacted)

---

## FAQ

### General Questions

**Q: How is Akashica different from Git?**

A: Akashica is designed specifically for content management, not source code:
- **Optimized for large files**: No 100MB file size limits
- **Simpler workflow**: No merge conflicts or rebase complexity
- **Content-addressed**: Automatic deduplication across entire repository
- **Multi-backend**: Native S3 support for cloud-scale storage
- **Two-tier model**: Separate immutable history from mutable workspaces

Best analogy: "Git for content, not code"

---

**Q: Can I use Akashica for source code?**

A: Yes, but Git is better suited for source code. Akashica is optimized for:
- Large binary files (images, videos, PDFs)
- Frequent concurrent editing
- Compliance and audit requirements
- Cloud-native storage (S3)

Use Git for: Code, small text files, complex branching/merging

---

**Q: How much does it cost to run Akashica?**

A: **Local storage**: Free (uses your hardware)

**S3 storage** (example):
```
1 TB content library:
- Storage: $23/month ($0.023/GB)
- Requests: ~$5/month (PUT/GET operations)
- Transfer: $0-90/month (depending on access patterns)

Total: ~$30-120/month for 1TB
```

**Cost optimization**:
- Use S3 Intelligent-Tiering for infrequent access
- Enable compression for large files
- Archive old commits to S3 Glacier

---

**Q: Can multiple people work on the same file simultaneously?**

A: Yes, with caveats:
- Each person gets their own **workspace** (isolated copy)
- Changes are independent until committed
- **Last commit wins** when publishing to branch
- No automatic merging—coordinate to avoid overwriting

**Best practice**: Communicate before editing shared files. Use workflow management tools (Slack, Jira) to coordinate.

---

**Q: How do I migrate existing content to Akashica?**

A: Simple migration process:
```bash
# 1. Initialize Akashica repository
cd /my-existing-content
akashica init

# 2. Create initial workspace
akashica checkout main

# 3. Copy all existing content
akashica cp . aka:/// --recursive

# 4. Commit as initial state
akashica commit -m "Initial import of existing content"
```

**Note for large migrations**:
- **Current file size limit**: No hard limit, but files >100MB may be slow to upload
- Consider copying in batches (by directory) to monitor progress
- Use local storage first for large imports, then migrate to S3
- Test with a subset of files before full migration
- For very large files (multiple GB), consider alternative solutions or wait for streaming support

Existing files remain on disk. Akashica creates versioned copies in `.akashica/`.

---

### Technical Questions

**Q: What happens if two people commit at the same time?**

A: Akashica uses **optimistic concurrency control**:
1. Alice commits first → branch updated to @5001
2. Bob commits 1 second later → branch updated to @5002
3. Result: Linear history, no conflicts

Branch pointer uses compare-and-swap (CAS) to ensure sequential updates.

---

**Q: Can I delete old commits to save space?**

A: Not currently supported. Commits are immutable and permanent.

**Workaround**: Implement lifecycle policies at storage layer:
```bash
# S3: Archive commits older than 1 year
aws s3api put-bucket-lifecycle-configuration \
  --bucket my-repo \
  --lifecycle-configuration '{
    "Rules": [{
      "Id": "ArchiveOldCommits",
      "Prefix": "commits/",
      "Status": "Enabled",
      "Transitions": [{
        "Days": 365,
        "StorageClass": "GLACIER"
      }]
    }]
  }'
```

---

**Q: How does content deduplication work?**

A: Akashica uses **content-addressed storage**:
1. Each file is hashed (SHA-256)
2. Content stored once under hash: `objects/<hash>`
3. Multiple files with same content reference same object

**Example**:
```
File: logo.svg (hash: abc123...)
Paths referencing it:
- /branding/logo.svg → objects/abc123...
- /campaigns/q4/logo.svg → objects/abc123...
- /archive/2024/logo.svg → objects/abc123...

Storage used: 1 copy (deduplication)
```

**Savings**: Typically 40-60% for content repositories with duplicates

---

**Q: Can I use Akashica programmatically (API)?**

A: Yes, via Swift library:
```swift
import Akashica
import AkashicaS3Storage

// Initialize repository
let storage = try await S3StorageAdapter(
    region: "us-east-1",
    bucket: "my-content-repo"
)
let repo = AkashicaRepository(storage: storage)

// Create workspace
let workspace = try await repo.createWorkspace(fromBranch: "main")
let session = await repo.session(workspace: workspace)

// Write file
let data = "Hello, World!".data(using: .utf8)!
try await session.writeFile(data, to: "hello.txt")

// Commit
let commit = try await repo.publishWorkspace(
    workspace,
    toBranch: "main",
    message: "Add hello.txt",
    author: "api@company.com"
)

print("Published commit: \(commit)")
```

See `docs/API_IMPLEMENTATION_SUMMARY.md` for full API reference.

---

**Q: What are the scalability limits?**

A: **Local storage**:
- Limited by disk space
- Recommended: <1TB per repository

**S3 storage**:
- No practical limit (petabytes supported)
- Single file limit: 5TB (S3 maximum)
- Files per directory: No limit (uses pagination)

**Performance**:
- Commit creation: O(n) where n = changed files
- File read: O(1) - direct hash lookup
- Directory listing: O(m) where m = entries in directory

---

**Q: Is Akashica production-ready?**

A: Current status:
- ✅ Core functionality: Stable and tested (160 tests passing)
- ✅ CLI: Feature-complete with aka:// URI support
- ✅ S3 backend: Production-ready with pagination and CAS
- ⚠️ Advanced features: Merge, garbage collection not yet implemented
- ⚠️ Documentation: Comprehensive but new (community feedback pending)

**Recommendation**: Production-ready for content management. Not yet recommended for mission-critical systems without backup strategy.

---

**Q: How do I back up my Akashica repository?**

A: **S3 backend**: Use S3 replication
```bash
aws s3api put-bucket-replication \
  --bucket my-content-repo \
  --replication-configuration '{
    "Role": "arn:aws:iam::...:role/replication-role",
    "Rules": [{
      "Status": "Enabled",
      "Priority": 1,
      "Destination": {
        "Bucket": "arn:aws:s3:::backup-bucket"
      }
    }]
  }'
```

**Local storage**: Regular filesystem backups
```bash
# Daily backup
rsync -av /my-content/.akashica/ /backup/akashica-$(date +%Y%m%d)/

# Or use tar
tar -czf akashica-backup-$(date +%Y%m%d).tar.gz .akashica/
```

**Recovery**: Simply restore `.akashica/` directory and reinitialize.

---

**Q: Can I use Akashica offline?**

A: **Local storage**: Fully offline-capable

**S3 storage**: Requires internet connection for all operations

**Hybrid approach**:
1. Clone to local for offline work:
```bash
akashica init --local  # Local mode
akashica cp aka://main/. ./ --recursive  # Download all
```

2. Sync back to S3 when online:
```bash
# Manual sync (not currently automated)
```

---

**Q: What's the roadmap for future features?**

A: Planned enhancements:
- **Merge support**: Combine changes from multiple workspaces
- **Garbage collection**: Reclaim space from unreferenced objects
- **Cross-commit diff**: Compare any two commits
- **Streaming API**: Handle files >5GB
- **Conflict resolution**: Tools for resolving concurrent edits
- **Google Cloud Storage**: GCS backend support

See `docs/design.md` for detailed roadmap.

---

### Business Questions

**Q: Do I need a license?**

A: Check project repository for current licensing terms. Typically open-source for non-commercial use.

---

**Q: Is enterprise support available?**

A: Contact project maintainers for:
- Commercial support contracts
- Training for teams
- Custom feature development
- Deployment assistance
- SLA guarantees

---

**Q: Can Akashica replace our current CMS?**

A: Akashica is a **version control system**, not a full CMS. It provides:
- ✅ Content storage and versioning
- ✅ Change tracking and audit trail
- ✅ Concurrent editing workflows

It does NOT provide:
- ❌ Web UI for content editing
- ❌ User management and permissions
- ❌ Workflows and approval processes
- ❌ Preview and rendering

**Best use**: Backend storage layer for custom CMS, or standalone for technical teams.

---

**Q: What support is available?**

A: **Community support** (free):
- GitHub Issues
- Documentation
- Example code

**Commercial support** (contact maintainers):
- Priority bug fixes
- Custom feature development
- Training and onboarding
- Architecture consultation
- 24/7 emergency support

---

## Conclusion

Akashica provides production-ready version control for content management. The two-tier model (immutable commits + mutable workspaces) enables safe concurrent editing while maintaining complete audit history.

**Key takeaways**:
- Use **local storage** for development, **S3** for production
- The **two-tier model** separates permanent history from temporary work
- **aka:// URIs** provide explicit, unambiguous content addressing
- Follow **best practices** for commit messages, branching, and security
- **Audit trail** is automatic—every change is tracked forever

**Your next steps**:
1. Set up your first repository (local or S3)
2. Practice the basic workflow (checkout, edit, commit)
3. Explore advanced features (branch reading, historical access)
4. Implement team workflows and policies
5. Monitor and optimize as you scale

**Additional resources**:
- [URI Scheme](URI_SCHEME.md): Complete aka:// specification
- [Architecture](ARCHITECTURE.md): Session-first design details
- [API Reference](API_IMPLEMENTATION_SUMMARY.md): Programmatic access

**Questions?** Open an issue or contact the project maintainers.

---

*Last updated: October 2025*
*Akashica version: 1.0.0*
