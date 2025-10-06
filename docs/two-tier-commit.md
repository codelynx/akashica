## Workspace Model

### 1. Overview
Akashica provides two modes for accessing repository content:

1. **Committed Repository Mode**: Read-only access to immutable, published commits
2. **Workspace Mode**: Read-write access to an isolated working directory that builds on top of a committed state

This separation allows users to make changes in isolation without affecting the canonical repository history until they explicitly publish their work.

### 2. Objective
- **Purpose**: Layer ephemeral workspace state on top of canonical branch commits to enable fast, isolated iterations without rewriting base history until publication.
- **Scope**: Applies to CLI, API, and service flows that clone branches, stage modifications, and publish new immutable commits.

### 3. Terminology
- **Branch Head (`@1002`)**: An immutable commit ID referenced by `branches/<name>.json`. This represents the canonical, published state of a branch.
- **Workspace ID (`$a1b3`)**: A random suffix appended to the base commit ID to create a workspace reference (`@1002$a1b3`). This identifies an isolated working environment.
- **Committed Access (`@1002`)**: Reading files from the canonical commit resolves directly through content-addressed objects in `objects/{hash}.dat`.
- **Workspace Access (`@1002$a1b3`)**: Reading or writing files in a workspace checks `changeset/@1002$a1b3/` first, then falls back to the base commit's objects for unchanged files.
- **Object Hash (`{hash-6}`)**: Content-addressed entries that resolve to `objects/<prefix>/<hash>.dat` or `.dir` files as defined in the primary repository layout.

### 4. How the Two Modes Work

#### Committed Repository Mode (Reading `@1002`)
When you access a file from a committed state like `@1002/japan/tokyo/banana.txt`:
1. Start at `changeset/@1002/.dir` to get the root manifest
2. Look up `japan/` entry to find its hash, then read `objects/{hash}.dir`
3. Look up `tokyo/` entry to find its hash, then read `objects/{hash}.dir`
4. Look up `banana.txt` entry to find its hash, then read `objects/{hash}.dat`
5. Return the file content

This is read-only. All data comes from immutable, content-addressed objects.

#### Workspace Mode (Reading/Writing `@1002$a1b3`)
When you access a file from a workspace like `@1002$a1b3/japan/tokyo/banana.txt`:

**For reads:**
1. Check workspace `.dir`: `changeset/@1002$a1b3/objects/japan/tokyo/.dir`
   - If `.dir` doesn't exist or `banana.txt` not listed → fall back to base commit `@1002`
2. If `banana.txt` listed in `.dir`, try these in order:
   - Check `changeset/@1002$a1b3/objects/japan/tokyo/banana.txt` → if exists, read modified content
   - Check `changeset/@1002$a1b3/refs/japan/tokyo/banana.txt` → if exists, read COW reference, resolve hash from base commit
   - Otherwise → fall back to base commit `@1002`

**For writes (modify existing file):**
1. Write new content to `changeset/@1002$a1b3/objects/japan/tokyo/banana.txt`
2. Update workspace `.dir` to include `banana.txt` (if not already listed)
3. Delete any COW reference in `refs/` (if it existed)
4. Base commit `@1002` remains unchanged

**For renames (unchanged content):**
1. Create COW reference: `changeset/@1002$a1b3/refs/japan/peach_renamed.txt`
   ```json
   {
     "base_path": "japan/peach.txt",
     "hash": "{hash-5a}",
     "size": 1234
   }
   ```
2. Update workspace `.dir` to include `peach_renamed.txt` and remove `peach.txt`
3. No actual file content copied to workspace `objects/`

### 5. Storage Layout Example

#### Workspace Structure
Workspaces use two separate directories:
- `objects/` - stores actually modified file content
- `refs/` - stores copy-on-write (COW) references to unchanged files

```
# Initial committed state
branch main -> @1002                              # canonical branch head

changeset/@1002/.dir:
    {file-hash-1a}:{size}:README.txt
    {dir-hash-2a}:{size}:japan/

objects/{dir-hash-2a}.dir:
    {dir-hash-3a}:{size}:tokyo/
    {file-hash-5a}:{size}:peach.txt

objects/{dir-hash-3a}.dir:
    {file-hash-7a}:{size}:banana.txt              # banana v1

objects/{file-hash-7a}.dat                        # actual content of banana v1

# After creating workspace and editing banana.txt
branch main -> @1002$a1b3                         # now points at workspace

changeset/@1002$a1b3/
  objects/
    japan/
      .dir:
        """
        peach.txt
        tokyo/
        """
      tokyo/
        .dir:
          """
          banana.txt
          """
        banana.txt                                # banana v2 (modified content)
  refs/                                           # COW references (empty - no renames yet)

# Base commit unchanged
changeset/@1002/...                               # still has banana v1
objects/{file-hash-7a}.dat                        # still has banana v1
```

#### After Rename Operation
```
# User renames japan/peach.txt -> japan/peach_renamed.txt (content unchanged)

changeset/@1002$a1b3/
  objects/
    japan/
      .dir:
        """
        peach_renamed.txt
        tokyo/
        """
      tokyo/
        .dir:
          """
          banana.txt
          """
        banana.txt                                # banana v2 (modified)
  refs/
    japan/
      peach_renamed.txt:                          # COW reference
        """
        {
          "base_path": "japan/peach.txt",
          "hash": "{hash-5a}",
          "size": 1234
        }
        """
```

Key points:
- **Workspace `.dir` manifests** are name-based (simple file list), not hash-based
- **Modified files** are stored in `objects/` with actual content
- **Renamed/copied unchanged files** use COW references in `refs/` (avoids duplicate storage)
- **Unchanged files** have no workspace entry at all; reads fall back to base commit
- The base commit `@1002` and its objects remain completely untouched

### 6. Workspace Lifecycle

#### Creating a Workspace (Checkout)
1. User requests to work on branch `main` which points to commit `@1002`
2. Generate random workspace ID (e.g., `a1b3`)
3. Create workspace reference `@1002$a1b3`
4. Initialize empty workspace structure under `changeset/@1002$a1b3/`
5. Create `workspace.json` metadata file with parent commit, creator, and timestamp
6. Update branch pointer: `branches/main.json` now points to `@1002$a1b3`

At this point, reads from the workspace will fall back to `@1002` since no files have been modified yet.

#### Making Changes (Mutation)
1. User writes to `@1002$a1b3/japan/tokyo/banana.txt`
2. New content is stored at `changeset/@1002$a1b3/japan/tokyo/banana.txt`
3. Update `changeset/@1002$a1b3/japan/tokyo/.dir` to include `banana.txt`
4. Update parent manifests (`changeset/@1002$a1b3/japan/.dir` and `changeset/@1002$a1b3/.dir`) if needed
5. Base commit `@1002` remains unchanged

Now reads from `@1002$a1b3/japan/tokyo/banana.txt` will return the workspace version, while other unchanged files still fall back to `@1002`.

#### Checking Status (Diff & Validation)
1. Compare workspace manifests in `changeset/@1002$a1b3/` with base manifests in `changeset/@1002/`
2. Identify which files are new, modified, or deleted
3. Fast operation even for large repositories since only manifest comparison is needed

#### Publishing Changes (Commit)
1. Process all files in workspace `.dir` manifests:
   - **Modified files** (in `objects/`): Hash content and write to `{root}/objects/{hash}.dat`
   - **COW references** (in `refs/`): Reuse the hash from reference (deduplication)
   - Unchanged files: Reference existing hashes from base commit
2. Generate new `.dir` manifests with hash-based format: `{hash}:{size}:{name}`
3. Write new directory manifests to `objects/{hash}.dir`
4. Create new commit `@1003` pointing to root manifest hash
5. Update `branches/main.json` to point to `@1003` (using compare-and-swap to prevent conflicts)
6. Delete entire workspace directory: `rm -rf changeset/@1002$a1b3/`
7. The new commit `@1003` is now the canonical branch head

**Example: Rename with same content**
- Workspace has COW reference: `refs/japan/peach_renamed.txt` → hash `{hash-5a}`
- On commit: Check if `objects/{hash-5a}.dat` exists → yes, reuse it
- New manifest: `{hash-5a}:{size}:peach_renamed.txt`
- No duplicate storage, just new name in manifest

#### Discarding Changes (Abort)
1. Delete entire `changeset/@1002$a1b3/` directory
2. Revert `branches/main.json` to point back to base commit `@1002`
3. No objects were created in the shared object store, so nothing to clean up

### 7. Concurrency & Isolation

#### Multiple Workspaces on Same Commit
- User A creates workspace `@1002$a1b3`
- User B creates workspace `@1002$x9z7`
- Both work independently on top of commit `@1002`
- Each has their own `changeset/@1002$<id>/` directory
- No lock contention or conflict until publish time

#### Publishing with Conflicts
- User A publishes first: `@1002` → `@1003`
- User B's workspace `@1002$x9z7` is now based on outdated commit
- When User B tries to publish, compare-and-swap on `branches/main.json` will fail
- User B must rebase: create new workspace `@1003$y2k8` and replay changes on top of `@1003`

#### Reading Committed vs Workspace
- API requests to `@1002/...` always read from immutable objects
- API requests to `@1002$a1b3/...` check workspace first, then fall back to `@1002`
- Different users can simultaneously read `@1002` while another user modifies `@1002$a1b3`
- Branch pointer determines which mode is active for that branch

#### Garbage Collection
- When workspace publishes to `@1003`, delete `changeset/@1002$a1b3/`
- When workspace is aborted, delete `changeset/@1002$a1b3/`
- Objects in shared `objects/` store are preserved (may be referenced by other commits)
- Unreferenced objects become GC candidates according to repository retention policies

### 8. Copy-on-Write (COW) Optimization

#### Problem: Workspace Storage Bloat
Without COW, operations like rename or copy would duplicate file content in the workspace:
```
# Without COW: rename duplicates 1GB file
@1002$a1b3/objects/japan/large_file_renamed.dat  # 1GB duplicate!
```

#### Solution: COW References
Instead of copying content, create a lightweight reference in `refs/`:
```
@1002$a1b3/refs/japan/large_file_renamed.dat:
{
  "base_path": "japan/large_file.dat",
  "hash": "{hash-abc}",
  "size": 1073741824
}
```

#### Operations with COW

**Rename (unchanged content):**
1. User: `mv japan/peach.txt japan/peach_renamed.txt`
2. Create COW ref: `refs/japan/peach_renamed.txt` → points to `japan/peach.txt` with hash `{hash-5a}`
3. Update `.dir`: remove `peach.txt`, add `peach_renamed.txt`
4. Storage cost: ~100 bytes (JSON ref), not full file size

**Copy (unchanged content):**
1. User: `cp japan/peach.txt usa/peach.txt`
2. Create COW ref: `refs/usa/peach.txt` → points to `japan/peach.txt` with hash `{hash-5a}`
3. Update `.dir`: add `peach.txt` to both `japan/` and `usa/`
4. Storage cost: ~100 bytes per copy

**Edit after rename:**
1. User edits `japan/peach_renamed.txt`
2. Delete COW ref: `rm refs/japan/peach_renamed.txt`
3. Write actual content: `objects/japan/peach_renamed.txt`
4. Now content diverges from original

**On commit (deduplication):**
1. Process COW ref `refs/japan/peach_renamed.txt`:
   - Read hash `{hash-5a}` from reference
   - Check if `{root}/objects/{hash-5a}.dat` exists → yes
   - Reuse existing object in new manifest
2. Process modified file `objects/japan/lemon.txt`:
   - Hash content → `{hash-8b}` (new hash)
   - Write to `{root}/objects/{hash-8b}.dat` (new object)

#### Benefits
- **No duplicate storage** for renames/copies in workspace
- **Fast operations** (write small JSON file, not full content)
- **Automatic deduplication** on commit (reuses existing hashes)
- **Publisher-side only** (end users never see workspace complexity)

### 9. Benefits & Considerations

#### Why This Design Works

**Fast Iteration**
- Users modify workspace files without touching the immutable commit
- No coordination overhead until publish time
- Multiple users can work on the same base commit simultaneously

**Efficient Storage**
- Unchanged files require no workspace storage (fall back to base commit)
- Only modified files are stored in workspace
- Content-addressed objects are deduplicated across all commits and workspaces

**Clear History**
- Only published commits (`@1001`, `@1002`, `@1003`) appear in branch history
- Workspace activity is ephemeral and doesn't clutter the timeline
- Workspace metadata can be retained for auditing if needed

**Granular Access Control**
- Branch-level permissions control who can read/write committed state
- Workspace-level ownership controls who can modify a specific workspace
- Different users can have different workspaces on the same branch

**Failure Recovery**
- Crashes during workspace edits don't affect the base commit
- Workspace can be discarded and recreated without risk
- Partial uploads can be retried without corrupting canonical state
- Publishing failures can be rolled back by deleting the new commit and keeping workspace intact

#### Trade-offs

**Branch Pointer Complexity**
- Branch pointer can reference either a commit (`@1002`) or a workspace (`@1002$a1b3`)
- Resolution logic must check workspace first, then fall back to base commit
- More complex than a pure commit-only model

**Workspace Cleanup Required**
- Orphaned workspaces (user disconnects, abandons work) need cleanup policies
- Must track workspace age and automatically expire stale workspaces
- Need monitoring to prevent workspace storage from growing unbounded
- COW references in `refs/` mitigate storage bloat from renames/copies

**Publishing Requires Rebase on Conflict**
- If base commit changes while working in workspace, cannot directly publish
- Must create new workspace on latest commit and replay changes
- More complex than a system where conflicts are detected during edits
