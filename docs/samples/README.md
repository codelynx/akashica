# Akashica Storage Structure Samples

This directory contains step-by-step examples showing the physical storage structure of an Akashica repository as it evolves through commits and workspace operations.

**Note on hashes:** In production, Akashica uses full SHA-256 hashes (64 hex characters). For readability in these samples, most steps use shortened placeholder hashes like `a1f3e2b4c5d6`. Step 0 demonstrates real SHA-256 hashes.

## Story: Travel Blog Repository

A travel blog repository that demonstrates:
- Initial commit with basic structure
- Adding new files and directories
- Creating a workspace
- Making changes in workspace (edit, add, rename, delete, COW references)
- Publishing workspace as a new commit

## Directory Structure

```
samples/
├── step0-initial-commit/     # @1001: Initial commit
├── step1-second-commit/      # @1002: Added more destinations
├── step2-create-workspace/   # @1002$a1b3: Workspace created
├── step3-workspace-operations/ # Workspace with changes
└── step4-commit-workspace/   # @1003: Workspace published
```

---

## Step 0: Initial Commit (@1001)

**User view:**
```
README.md
asia/
  japan/
    tokyo.txt
    kyoto.txt
  thailand/
    bangkok.txt
```

**Storage structure:**
```
root/
├── branches/
│   └── main.json           # {"HEAD": "@1001"}
├── changeset/
│   └── @1001/
│       └── .dir            # Root manifest with SHA-256 hashes
└── objects/
    ├── a7d8f966...29499d.dat    # README.md content (SHA-256 hash)
    ├── 324fe7e9...0e62c8c.dir    # asia/ manifest
    ├── 7bf72f6e...b6c80c51.dir   # asia/japan/ manifest
    ├── [thailand.dir hash].dir   # asia/thailand/ manifest
    ├── 7f4833ea...dff6eafb.dat   # tokyo.txt content
    ├── [kyoto.txt hash].dat      # kyoto.txt content
    └── [bangkok.txt hash].dat    # bangkok.txt content
```

**Example manifest (`changeset/@1001/.dir`):**
```
a7d8f9665a653f26e9383af16c50b2788315019df6cca8cfca608087c629499d:163:README.md
324fe7e9ee480b30ba008a4e0cf56e1ce2ddf2d723ceb15418f088a440e62c8c:153:asia/
```

**Key points:**
- All content is content-addressed via SHA-256 hashes (64 hex characters)
- `.dir` files use format: `{sha256}:{size}:{name}`
- All objects are immutable
- See `step0-initial-commit/` for actual files with real SHA-256 hashes

---

## Step 1: Second Commit (@1002)

**Changes:**
- Added `asia/japan/osaka.txt`
- Added `asia/thailand/phuket.txt`
- Added `europe/france/paris.txt`

**User view:**
```
README.md
asia/
  japan/
    tokyo.txt
    kyoto.txt
    osaka.txt         # NEW
  thailand/
    bangkok.txt
    phuket.txt        # NEW
europe/               # NEW
  france/
    paris.txt         # NEW
```

**Storage structure:**
```
root/
├── branches/
│   └── main.json           # {"HEAD": "@1002"}  ← updated
├── changeset/
│   ├── @1001/             # old commit preserved
│   └── @1002/             # new commit
│       └── .dir            # new root manifest
└── objects/
    ├── [all from @1001]    # reused
    ├── a1b3c5d7e9f0.dat    # osaka.txt (new)
    ├── b2c4d6e8f0a1.dat    # phuket.txt (new)
    ├── b8c0d2e4f6a1.dir    # asia/ manifest (updated)
    ├── c9d1e3f5a7b2.dir    # europe/ manifest (new)
    ├── d0e2f4a6b8c1.dir    # asia/japan/ manifest (updated)
    ├── d3e5f7a9b1c4.dir    # europe/france/ manifest (new)
    └── e4f6a8b0c2d5.dat    # paris.txt (new)
```

**Key points:**
- Unchanged files (tokyo.txt, kyoto.txt, bangkok.txt) are reused via same hash
- Only new/modified manifests and files are written to objects/
- Old commit @1001 is preserved

---

## Step 2: Create Workspace (@1002$a1b3)

**Operation:** User creates workspace to start editing

**Storage structure:**
```
root/
├── branches/
│   └── main.json           # {"HEAD": "@1002$a1b3"}  ← points to workspace
├── changeset/
│   ├── @1002/             # base commit
│   └── @1002$a1b3/        # NEW workspace
│       ├── workspace.json  # metadata: base=@1002, creator, timestamp
│       ├── objects/        # empty (no changes yet)
│       └── refs/           # empty (no COW refs yet)
└── objects/
    └── [unchanged]
```

**Key points:**
- Workspace created with empty `objects/` and `refs/`
- `workspace.json` records base commit and metadata
- Branch pointer now references workspace, not commit
- All reads fall back to base commit @1002

---

## Step 3: Workspace Operations

**Changes:**
1. ✏️  **Edit** `asia/japan/tokyo.txt` (add content)
2. ➕ **Add** `asia/japan/hiroshima.txt` (new file)
3. 🔄 **Rename** `asia/japan/kyoto.txt` → `kyoto_guide.txt` (unchanged content, COW)
4. 📋 **Copy** `europe/france/paris.txt` → `paris_backup.txt` (unchanged content, COW)
5. ❌ **Delete** `asia/thailand/phuket.txt`
6. ✏️  **Edit** `europe/france/paris.txt` (add content)

**Storage structure:**
```
root/
├── branches/
│   └── main.json           # {"HEAD": "@1002$a1b3"}
├── changeset/
│   ├── @1002/             # base commit (unchanged)
│   └── @1002$a1b3/
│       ├── workspace.json
│       ├── objects/
│       │   ├── .dir:
│       │   │   README.md
│       │   │   asia/
│       │   │   europe/
│       │   ├── asia/
│       │   │   ├── .dir:
│       │   │   │   japan/
│       │   │   │   thailand/
│       │   │   ├── japan/
│       │   │   │   ├── .dir:
│       │   │   │   │   tokyo.txt
│       │   │   │   │   kyoto_guide.txt
│       │   │   │   │   osaka.txt
│       │   │   │   │   hiroshima.txt
│       │   │   │   ├── tokyo.txt       # MODIFIED content
│       │   │   │   └── hiroshima.txt   # NEW content
│       │   │   └── thailand/
│       │   │       └── .dir:
│       │   │           bangkok.txt     # phuket.txt deleted (not listed)
│       │   └── europe/
│       │       ├── .dir:
│       │       │   france/
│       │       └── france/
│       │           ├── .dir:
│       │           │   paris.txt
│       │           │   paris_backup.txt
│       │           └── paris.txt       # MODIFIED content
│       └── refs/
│           ├── asia/
│           │   └── japan/
│           │       └── kyoto_guide.txt # COW ref to kyoto.txt
│           └── europe/
│               └── france/
│                   └── paris_backup.txt # COW ref to paris.txt (old version)
└── objects/
    └── [unchanged - base commit objects]
```

**COW reference example (`refs/asia/japan/kyoto_guide.txt`):**
```json
{
  "base_path": "asia/japan/kyoto.txt",
  "hash": "f6a8b0c2d4e5",
  "size": 76
}
```

**Key points:**
- **Modified files** stored in workspace `objects/` with actual content
- **New files** stored in workspace `objects/`
- **Renamed files (unchanged)** use COW references in `refs/` (no content duplication)
- **Copied files (unchanged)** use COW references in `refs/`
- **Deleted files** removed from `.dir` manifests
- **Unchanged files** not in workspace at all (fall back to @1002)
- Workspace `.dir` files use **name-based** format (simple list), not hash-based

---

## Step 4: Commit Workspace (@1003)

**Operation:** Publish workspace changes as new commit

**Storage structure:**
```
root/
├── branches/
│   └── main.json           # {"HEAD": "@1003"}  ← points to new commit
├── changeset/
│   ├── @1002/             # old commit preserved
│   ├── @1002$a1b3/        # DELETED (workspace published)
│   └── @1003/             # NEW commit
│       └── .dir            # hash-based manifest
└── objects/
    ├── [all from @1002]    # reused where unchanged
    ├── f1a3b5c7d9e2.dir    # asia/ manifest (updated)
    ├── g2b4c6d8e0f3.dir    # europe/ manifest (updated)
    ├── h3c5d7e9f1a4.dir    # asia/japan/ manifest (updated)
    ├── i4d6e8f0a2b5.dat    # tokyo.txt v2 (modified)
    ├── j5e7f9a1b3c6.dat    # hiroshima.txt (new)
    ├── k6f8a0b2c4d7.dir    # europe/france/ manifest (updated)
    └── l7a9b1c3d5e8.dat    # paris.txt v2 (modified)
```

**Deduplication on commit:**
- `kyoto_guide.txt` → COW ref has hash `f6a8b0c2d4e5` → reuse existing object
- `paris_backup.txt` → COW ref has hash `e4f6a8b0c2d5` → reuse existing object
- `osaka.txt`, `bangkok.txt` → unchanged → reuse existing objects
- `tokyo.txt`, `paris.txt` → modified → hash new content, write new objects
- `hiroshima.txt` → new → hash content, write new object

**@1003/.dir manifest:**
```
a1f3e2b4c5d6:156:README.md           # reused from @1002
f1a3b5c7d9e2:896:asia/               # updated
g2b4c6d8e0f3:412:europe/             # updated
```

**objects/h3c5d7e9f1a4.dir (asia/japan/):**
```
i4d6e8f0a2b5:128:tokyo.txt           # new hash (modified)
f6a8b0c2d4e5:76:kyoto_guide.txt      # SAME hash (renamed via COW)
a1b3c5d7e9f0:82:osaka.txt            # reused hash (unchanged)
j5e7f9a1b3c6:87:hiroshima.txt        # new hash (new file)
```

**Key points:**
- Workspace deleted after successful publish
- COW references resolved to hashes, deduplicated against existing objects
- Only new/modified content written to objects/
- Manifest back to hash-based format: `{hash}:{size}:{name}`
- Branch pointer updated to new commit
- Old commit @1002 preserved in history

---

## Summary: Committed vs Workspace Access

| Aspect | Committed Mode (`@1002`) | Workspace Mode (`@1002$a1b3`) |
|--------|-------------------------|------------------------------|
| **Access** | Read-only | Read-write |
| **Manifest format** | Hash-based: `{hash}:{size}:{name}` | Name-based: just `name` |
| **Resolution** | Direct via content-addressed objects | Check `objects/` → `refs/` → fallback to base |
| **Storage** | Immutable, deduplicated | COW for renames/copies, actual content for edits |
| **Lifetime** | Permanent (until GC) | Ephemeral (until publish/abort) |
| **Use case** | Serving end users | Publisher editing |

---

## File Resolution Examples

### Read `@1002$a1b3/asia/japan/kyoto_guide.txt` (renamed, unchanged):
1. Check `changeset/@1002$a1b3/objects/asia/japan/.dir` → finds `kyoto_guide.txt`
2. Check `changeset/@1002$a1b3/objects/asia/japan/kyoto_guide.txt` → not found
3. Check `changeset/@1002$a1b3/refs/asia/japan/kyoto_guide.txt` → found!
   ```json
   {"base_path": "asia/japan/kyoto.txt", "hash": "f6a8b0c2d4e5", "size": 76}
   ```
4. Read `objects/f6a8b0c2d4e5.dat` → return content

### Read `@1002$a1b3/asia/japan/tokyo.txt` (modified):
1. Check `changeset/@1002$a1b3/objects/asia/japan/.dir` → finds `tokyo.txt`
2. Check `changeset/@1002$a1b3/objects/asia/japan/tokyo.txt` → found!
3. Read modified content directly from workspace

### Read `@1002$a1b3/asia/japan/osaka.txt` (unchanged):
1. Check `changeset/@1002$a1b3/objects/asia/japan/.dir` → finds `osaka.txt`
2. Check `changeset/@1002$a1b3/objects/asia/japan/osaka.txt` → not found
3. Check `changeset/@1002$a1b3/refs/asia/japan/osaka.txt` → not found
4. **Fallback to base commit @1002:**
   - Read `changeset/@1002/objects/asia/japan/.dir` → find hash for `osaka.txt`
   - Read `objects/a1b3c5d7e9f0.dat` → return content

### Read `@1002$a1b3/asia/thailand/phuket.txt` (deleted):
1. Check `changeset/@1002$a1b3/objects/asia/thailand/.dir` → `phuket.txt` not listed
2. Return 404 (file deleted in workspace)

---

## Key Takeaways

1. **Workspace structure is simple:** `objects/` for changed files, `refs/` for COW references
2. **COW avoids duplication:** Renames and copies don't duplicate content in workspace
3. **Name-based workspace manifests:** Easy to update during editing
4. **Hash-based commit manifests:** Enables deduplication and immutability
5. **Fallback resolution:** Workspace reads fall back to base commit for unchanged files
6. **Deduplication on commit:** COW refs and unchanged files reuse existing object hashes
7. **Publisher-side only:** End users never see workspace complexity
