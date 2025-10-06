## Workspace Design Summary

### Core Concept
- Dual-tier commit model where immutable branch heads (`@1234`) represent published history and ephemeral workspace commits (`@1234$abcd`) capture in-progress changes.
- Workspaces mirror the base manifest but diverge via copy-on-write updates, enabling rapid iteration without mutating canonical commits.

### Storage Architecture
- Uses the shared object store (`objects/`) with SHA256-addressed payloads (`.dat` for data, `.dir` for manifests) introduced in `design.md`.
- Workspace manifests live under `@<base>$<workspace>/` alongside metadata (e.g., `workspace.json`), while branch pointers reside in `branches/<name>.json`.
- References reuse identical hashes across workspaces, keeping storage deduplicated and history consistent.

### Copy-on-Write Optimization
- Checkout clones manifests by reference; unchanged paths keep existing hashes.
- Modifications create new objects/manifests only for altered subtrees, preventing storage bloat even with many parallel workspaces.
- Garbage collection safely reclaims orphaned workspace objects after publish or abort events.

### Lifecycle Overview
1. **Checkout**: Generate a workspace ID, snapshot base manifests under `@<base>$<workspace>/`, and record metadata.
2. **Edit**: File changes stream into the object store, updating the workspace manifest entries for touched paths.
3. **Publish**: Freeze workspace manifests into a new first-tier commit, update branch pointer via compare-and-swap, and archive workspace records.
4. **Abort**: Delete workspace manifests/metadata; shared objects remain available due to hash reuse.

### Key Benefits
- Storage efficiency through deduplicated hashes and lazy materialization.
- Fast operations thanks to localized manifest updates and optimistic branch pointer writes.
- Contributor isolation: each workspace ID scopes edits, avoiding cross-user conflicts.
- Clean history: only first-tier commits appear in the immutable timeline, keeping review and auditing straightforward.

### Example Workflow & Costs
- Base commit `@1002` references 4 GB of media across 10 manifests.
- Workspace `@1002$a1b3` edits a single 200 MB video and updates a directory manifest.
- Resulting storage additions: 200 MB new `.dat` object + ~2 KB of manifest deltas; remaining 3.8 GB is fully reused.
- Publishing rolls workspace content into `@1003`, with GC later removing `@1002$a1b3` manifests once no longer referenced.

### Pitfalls & Mitigations
- **Stale Workspaces**: Long-lived workspaces may drift from branch head; mitigate by requiring rebase or refresh checks before publish.
- **CAS Conflicts**: Concurrent publishes can race on branch pointer updates; resolve via retry loops that regenerate workspaces off the latest head.
- **GC Timing**: Premature garbage collection could drop needed objects; enforce grace periods and reference counting before deletion.
- **Workspace Leakage**: Aborted sessions leaving metadata behind; provide scheduled sweeps to prune inactive workspace directories.

### Further Reading
- `docs/design.md`: Full storage format, manifest schema, and commit workflow.
- `docs/two-tier-commit.md`: Expanded two-tier model, concurrency details, and operational considerations.
- Sample manifests and object layouts located under `samples/` (if present) or generated via CLI walkthroughs.
