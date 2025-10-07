# Akashica URI Scheme Design

**Version:** 1.0.0
**Status:** Implementation In Progress
**Date:** 2025-10-07

## Overview

The `aka://` URI scheme provides explicit, unambiguous addressing for Akashica repository content. It replaces heuristic-based path detection with a clear scheme that supports different content scopes (workspaces, branches, commits).

## Design Goals

1. **Explicit over implicit**: No ambiguity about whether a path is local or remote
2. **Future-proof**: Support for branches, commits, and workspaces
3. **Read/write safety**: Clear indication of which scopes allow modifications
4. **Familiar syntax**: Similar to `file://`, `http://`, `s3://` URI schemes
5. **Backward compatibility**: Not a concern per user decision

## URI Format

```
aka:/path              # Relative path, current workspace
aka:///path            # Absolute path, current workspace
aka://<scope>/path     # Scoped path (branch or commit)
```

### Components

- **Scheme**: `aka:`
- **Slashes**:
  - Single `/` → relative path from current virtual CWD
  - Triple `///` → absolute path from repository root
  - Double `//` + scope → scoped access (branch/commit)
- **Scope** (authority): Identifies which version/context to access (branch or commit)
- **Path**: Path within the repository

## Scope Types

### 1. Current Workspace (No Scope)

**Format**:
- `aka:///path` - **Absolute path** from repository root
- `aka:/path` - **Relative path** from current virtual CWD

**Examples**:
```bash
# Absolute paths (from repository root)
aka:///reports/q3.pdf
aka:///japan/tokyo/data.txt

# Relative paths (from current virtual CWD)
aka:/design/mockup.png
aka:/./reports/q3.pdf
aka:/../osaka/data.txt
```

**Path Resolution**:
```bash
# Given current virtual CWD: /japan/tokyo
akashica pwd
# Output: /japan/tokyo

# Relative paths resolve from CWD
aka:/data.txt              → /japan/tokyo/data.txt
aka:/../osaka/data.txt     → /japan/osaka/data.txt
aka:/./subdir/file.txt     → /japan/tokyo/subdir/file.txt

# Absolute paths ignore CWD
aka:///reports/q3.pdf      → /reports/q3.pdf
aka:///usa/nyc/report.pdf  → /usa/nyc/report.pdf
```

**Rule**:
- **Triple slash** (`aka:///`) → absolute path from root
- **Single slash** (`aka:/`) → relative path from current virtual CWD

**Behavior**:
- References the current virtual workspace (staging area)
- **Read/write**: ✅ Allows modifications (cp, rm, mv)
- **Prerequisite**: Must have an active workspace (via `akashica checkout`)

### 2. Branch (Named Scope)

**Format**: `aka://<branch-name>/path`

**Examples**:
```
aka://main/config.yml
aka://develop/docs/readme.md
aka://feature/new-ui/assets/logo.png
```

**Behavior**:
- References the latest commit on the specified branch
- **Read/write**: ❌ Read-only (immutable view)
- **Use case**: Viewing production content, comparing versions

### 3. Commit (@ Prefix)

**Format**: `aka://@<commit-id>/path`

**Examples**:
```
aka://@1234/data/export.csv
aka://@5678/reports/annual-2024.pdf
```

**Behavior**:
- References a specific commit by ID
- **Read/write**: ❌ Read-only (immutable snapshot)
- **Use case**: Exact version retrieval, auditing

## Read/Write Rules

| Scope | Read | Write | Example |
|-------|------|-------|---------|
| Current workspace (absolute) | ✅ | ✅ | `aka:///draft.pdf` |
| Current workspace (relative) | ✅ | ✅ | `aka:/draft.pdf` |
| Branch | ✅ | ❌ | `aka://main/config.yml` |
| Commit | ✅ | ❌ | `aka://@1234/data.csv` |

**Write validation**: Commands like `cp`, `rm`, `mv` will check `AkaURI.isWritable` before performing modifications.

## Path Detection Logic

### Before (Heuristic)

Commands used heuristics to detect local vs remote paths:

```swift
func isLocalPath(_ path: String) -> Bool {
    // Heuristic: ~/file → local, file.txt → remote (maybe?)
    return path.hasPrefix("~/") || path.hasPrefix("./")
}
```

**Problems**:
- Bare names ambiguous: `file.txt` could be local or remote
- Absolute paths confusing: `/tmp/file` treated as repository path
- No way to reference other branches or commits

### After (Explicit)

Commands detect paths based on URI scheme:

```swift
if AkaURI.isAkaURI(path) {
    let uri = try AkaURI.parse(path)
    // Create session based on scope
    let session = try createSession(for: uri.scope)
    // Use uri.path as repository path
} else {
    // Treat as local filesystem path
}
```

**Benefits**:
- Explicit: `aka:///file.txt` = remote, `/tmp/file.txt` = local
- Unambiguous: No heuristics needed
- Future-proof: Supports branches, commits, workspaces

## Command Usage Examples

### Cat Command

```bash
# Read from current workspace (absolute)
akashica cat aka:///reports/q3.pdf > /tmp/q3.pdf

# Read from current workspace (relative)
akashica cd /japan/tokyo
akashica cat aka:/data.txt > /tmp/tokyo-data.txt
akashica cat aka:/../osaka/data.txt > /tmp/osaka-data.txt

# Read from branch
akashica cat aka://main/config.yml

# Read from specific commit
akashica cat aka://@1234/data/historical.csv > /tmp/old-data.csv
```

### Cp Command

```bash
# Upload to current workspace (absolute)
akashica cp /tmp/photo.jpg aka:///vacation/photo.jpg

# Upload to current workspace (relative)
akashica cd /vacation
akashica cp /tmp/photo.jpg aka:/photo.jpg
akashica cp /tmp/sunset.jpg aka:/./beach/sunset.jpg

# Download from branch (read-only)
akashica cp aka://main/report.pdf /tmp/report.pdf

# Download from commit (read-only)
akashica cp aka://@1234/export.csv /tmp/old-export.csv

# ❌ Error: Cannot write to branch
akashica cp /tmp/file.txt aka://main/file.txt
# Error: Cannot write to read-only scope 'branch: main'
```

### Ls Command

```bash
# List current workspace (absolute)
akashica ls aka:///projects/

# List current workspace (relative)
akashica cd /japan
akashica ls aka:/tokyo/
akashica ls aka:/../japan/osaka/

# List branch contents
akashica ls aka://main/

# List commit contents
akashica ls aka://@1234/reports/
```

### Rm/Mv Commands

```bash
# Modify current workspace (absolute)
akashica rm aka:///old-file.txt
akashica mv aka:///draft.pdf aka:///final.pdf

# Modify current workspace (relative)
akashica cd /drafts
akashica rm aka:/old-file.txt
akashica mv aka:/draft.pdf aka:/../final/published.pdf

# ❌ Error: Cannot modify branch
akashica rm aka://main/file.txt
# Error: Cannot delete from read-only scope 'branch: main'
```

## Backward Compatibility

**User decision**: "no worry about backward compatibility"

**Migration strategy**:
1. Remove all heuristic-based path detection
2. Update all commands to require `aka://` for repository paths
3. Treat all non-aka:// paths as local filesystem paths
4. Update documentation with new examples

**Breaking change**:
- Old: `akashica cat file.txt` (ambiguous - is it local or remote?)
- New:
  - `akashica cat aka:///file.txt` (explicit - remote, absolute)
  - `akashica cat aka:/file.txt` (explicit - remote, relative)
  - `akashica cat /tmp/file.txt` (explicit - local filesystem)

## Implementation Phases

### Phase 1: URI Parser ✅
- [x] Create `AkaURI.swift` with parser
- [x] Support all scope types (currentWorkspace, branch, commit, workspace)
- [x] Add `isWritable` property
- [x] Implement `parse()` and `toString()` methods

### Phase 2: Cp Command
- [ ] Update `Cp.swift` to use `AkaURI.parse()`
- [ ] Add scope validation (check `isWritable` for destination)
- [ ] Create session factory for different scopes
- [ ] Test upload/download with URIs

### Phase 3: Remaining Commands
- [ ] Update `Cat.swift` with URI support
- [ ] Update `Ls.swift` with URI support
- [ ] Update `Cd.swift` with URI support (workspace scope only)
- [ ] Update `Rm.swift` and `Mv.swift` with write validation

### Phase 4: Session Factory
- [ ] Add `Config.createSession(for scope:)` method
- [ ] Map scopes to session types:
  - `currentWorkspace` → workspace session
  - `branch` → branch session
  - `commit` → commit session

### Phase 5: Documentation
- [ ] Update `docs/VIRTUAL_FILESYSTEM.md` with aka:// examples
- [ ] Update command help text with URI syntax
- [ ] Add troubleshooting section for common URI errors

### Phase 6: Testing
- [ ] Test all scope types (workspace, branch, commit)
- [ ] Verify read/write validation
- [ ] Test error messages for invalid URIs
- [ ] End-to-end testing with S3

## Error Handling

### Parse Errors

```swift
enum AkaURIError: Error {
    case invalidScheme(String)      // Not aka:// or aka:/
    case missingPath(String)         // No path after scope
}
```

**Examples**:
```
aka:file.txt → invalidScheme
aka://main → missingPath (branch name without path)
```

### Runtime Errors

```swift
// Write validation
if !uri.isWritable {
    throw AkashicaError.readOnlyScope(uri.scopeDescription)
}

// Workspace required
if uri.scope == .currentWorkspace && config.currentWorkspace() == nil {
    throw AkashicaError.noWorkspace("Please run 'akashica checkout' first")
}
```

## Design Decisions

### Why `aka://` instead of `akashica://`?

**Rationale**: Shorter, easier to type, follows precedent (git vs git://)

### Why single slash for relative vs triple for absolute?

**Rationale**:
- Single slash (`aka:/path`) = minimal syntax for most common case (relative paths)
- Triple slash (`aka:///path`) = standard URI form (scheme + empty authority + absolute path)
- Double slash (`aka://scope/path`) = explicit scope (branch/commit)
- No ambiguity: slash count determines behavior

### Why `@` for commits?

**Rationale**:
- `@` follows Git convention (`git show @1234`)
- Visually distinct, no collision with branch names

### Why empty scope for current workspace?

**Rationale**: Most common use case should be shortest: `aka:///file.txt` or `aka:/file.txt`

### Why read-only for branches?

**Rationale**:
- Prevents accidental modifications to production content
- Forces workflow: checkout → modify → commit
- Matches Git model (can't write directly to remote branches)

## Future Extensions

### Cross-Repository References

```
aka://repo:my-other-repo/main/config.yml
```

**Use case**: Multi-repository projects, shared assets

### Query Parameters

```
aka://main/data.csv?version=2024-10-07
aka://main/image.jpg?quality=high
```

**Use case**: Content variants, transformations

### Fragments

```
aka://main/document.md#section-3
aka://main/data.csv#rows=10-20
```

**Use case**: Partial content access, range queries

## Comparison with Other Systems

| Feature | Git | S3 CLI | Akashica |
|---------|-----|--------|----------|
| **Scheme** | `git://` | `s3://` | `aka://` |
| **Branches** | `origin/main` | N/A | `aka://main/path` |
| **Commits** | `@1234:path` | N/A | `aka://@1234/path` |
| **Local** | Implicit | Explicit | Explicit (no `aka://`) |
| **Read-only** | No explicit marker | No | Yes (scope-based) |

## References

- RFC 3986: Uniform Resource Identifier (URI): Generic Syntax
- Git URI scheme: https://git-scm.com/book/en/v2/Git-on-the-Server-The-Protocols
- S3 URI scheme: https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-parameters-file.html

---

**Built with** [Claude Code](https://claude.com/claude-code)
