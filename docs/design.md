## Akashica Design Draft

### 1. Overview
- **Objective**: Provide a Swift-based content management framework that mirrors Git-like workflows for massive binary repositories (terabytes–petabytes) while supporting S3-compatible and local storage backends.
- **Core Principles**: Immutable history, content-addressed storage, pluggable storage adapters, strong consistency per branch, efficient large-object handling, and ergonomic developer tooling.

### 2. Key Use Cases
- **Large Media Pipelines**: Manage evolving collections of video, audio, or imaging assets with traceable versions.
- **Data Science Artifacts**: Version datasets, model outputs, and notebooks shared across distributed teams.
- **Enterprise Document Archives**: Maintain auditable history of compliance documents and internal knowledge bases.

### 3. Requirements Summary
- **Version Semantics**: Branches, commits, tags, and diff-capable manifests with no mutations to historical data.
- **Scalability**: Handle repositories containing billions of objects and directories with deep nesting.
- **Performance**: Support parallel uploads/downloads, resumable transfers, and paginated directory traversal.
- **Integrity**: Cryptographic hashing using SHA256 for all content addressing.
- **Durability**: Metadata persistence with transactional guarantees for branch updates; objects persisted in reliable storage.
- **Security**: Authentication/authorization hooks, encryption-at-rest (leveraging S3 SSE or local equivalents), and network isolation options.
- **Extensibility**: Plugin points for custom metadata, indexing, and notifications.

### 4. System Architecture
- **Swift Package Modules**
  - `AkashicaCore`: Domain models (changeset, manifest, branch), commit orchestration, diff utilities.
  - `AkashicaStorage`: Protocols for object and metadata stores, plus common utilities.
  - `AkashicaS3Adapter`: Implements storage protocols using AWS SDK or MinIO.
  - `AkashicaLocalAdapter`: Filesystem-backed implementation for local deployments.
  - `AkashicaCLI`: Command-line tooling (init, commit, diff, checkout, gc).
- **Supporting Services**
  - **Metadata Service**: Abstracts durable state for branches, tags, and transactional logs. Embeddable (SQLite) locally; scalable (DynamoDB/PostgreSQL) in distributed mode.
  - **Background Workers**: Optional components handling garbage collection, prefetch caching, and event fan-out.
- **Client Applications**: iOS/macOS apps, server-side Swift services, or other platforms interfacing via Swift bridging (e.g., via GRPC wrapper).

### 5. Data Model & Storage Layout
- **Changeset (`@<id>`)**
  - Metadata file `changeset/@<id>/meta.json` capturing author, timestamp, parents, message, and root manifest hash reference.
  - Root directory manifest is stored in the object store like any other directory manifest and referenced by hash from the metadata.
- **Branch Pointer (`branches/<branch>.json`)**
  - Minimal JSON: `{ "name": "main", "head": "@1002", "updated": "ISO8601" }` plus optional metadata.
- **Directory Manifest (`.dir`)**
  - Newline-delimited entries: `{hash}:{size}:{name}`; directories (including the repository root) are suffixed `/` and point to child manifest hashes.
  - The size field enables O(1) computation of total directory size by summing all entries, supporting instant progress tracking and quota checks without traversing objects.
- **Object Store (sharded by hash prefix)**
  - Path format: `objects/{hash[0:2]}/{hash[2:4]}/{hash[4:]}.{ext}` where hash is the full SHA256 hex string.
  - Payload files carry extensions: `.dat` for binary payloads, `.dir` for directory manifests.
  - Example: SHA256 `a3f2b8d9...` → `objects/a3/f2/b8d9c1e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9.dat`
  - Sharding provides 65,536 buckets (4 hex chars), scaling to petabytes while maintaining manageable directory sizes.
  - Works uniformly for both S3 (key prefixes) and local filesystem (nested directories).
- **Index Tables** (optional)
  - Secondary indexes for search/tagging stored in metadata service or external databases.
- **Repository Format Version**
  - Format version stored in repository root configuration (e.g., `.akashica/config.json`).
  - Migration between format versions requires full repository conversion; no partial or mixed-version support.
- **Sample Layout**
  ```
  root-storage/
    branches/
      main.json                      # { "name": "main", "head": "@1002" }
    changeset/
      @1002/
        meta.json                    # { "rootManifestHash": "a3f2b8d9...", ... }
    objects/
      a3/
        f2/
          b8d9c1e4f5a6...f9.dir      # root manifest (hash-4a equivalent)
      12/
        34/
          56789abc...def.dat         # README.md contents (hash-1a equivalent)
      89/
        ab/
          cdef0123...456.dat         # hello.txt contents (hash-2a equivalent)
      cd/
        ef/
          01234567...890.dat         # world.txt v2 contents (hash-3b equivalent)
      78/
        90/
          abcdef12...345.dir         # japan manifest (hash-5a equivalent)
      de/
        f0/
          12345678...9ab.dir         # tokyo manifest (hash-6a equivalent)
  ```
  - Example root manifest (`hash-4a`):
    ```
    hash-1a:12:README.md
    hash-2a:5:hello.txt
    hash-5a:57:japan/
    ```
  - Example nested manifest (`hash-5a`):
    ```
    hash-3b:11:world.txt
    hash-6a:44:tokyo/
    ```
  - Example deeper manifest (`hash-6a`):
    ```
    hash-7a:20:banana.txt
    ```

### 6. Workflow Details
- **Recording a Commit**
  - Stage operations through high-level APIs (add, update, delete, rename).
  - Compute hashes and upload new objects; reuse existing ones when hash matches.
  - Build manifests bottom-up: leaf files first, then parent directories, culminating in the root manifest hash.
  - Persist the root manifest into the object store and record its hash inside the changeset metadata.
  - Write changeset metadata and update branch pointer using optimistic concurrency (CAS or transactional record).
- **Fetching Content**
  - Resolve branch → head changeset → root manifest hash, then fetch the manifest via object store lookup.
  - Stream directory listings in pages; lazily fetch sub-manifests and objects on demand.
  - Provide convenience helpers for downloading entire paths or streaming byte ranges.
- **Branch & Merge Semantics**
  - Branch creation copies pointer metadata to new branch file.
  - Merge workflow uses three-way compare of manifests; conflicts flagged when same path diverges in target/base and source/base.
- **Garbage Collection**
  - Maintain reference counts or mark-and-sweep metadata for manifests/objects.
  - Retention policies configurable per repository; deletion occurs asynchronously after grace period.

### 7. Storage Adapter Contract
- **Capabilities Interface**
  - Indicates support for multipart uploads, server-side encryption, object versioning, read-after-write consistency, etc.
- **Primitive Operations**
  - `putObject`, `getObject`, `deleteObject`, `listObjects`, `putMetadata`, `compareAndSwap` (for branch updates), `lock` (optional advisory lock).
- **Error Handling**
  - Normalize storage-specific errors into framework-defined error taxonomy with retry policies and backoff strategies.
- **Instrumentation**
  - Emit metrics/traces hooks for latency, throughput, error rates; integrate with standard monitoring (e.g., Prometheus, CloudWatch).

### 8. Performance & Reliability
- **Concurrency Model**
  - Utilize Swift Concurrency (`async/await`, task groups) to parallelize network and hashing operations.
- **Caching Layers**
  - Local disk cache for manifests and frequently accessed objects.
  - In-memory LRU for metadata to minimize repeated manifest downloads.
- **Resilience**
  - Automatic retries with exponential backoff for transient errors.
  - Checkpointing for large uploads to allow resumable transfers.

### 9. Security & Compliance
- **Authentication**: Integrate with AWS IAM, signed URLs, or local credentials providers.
- **Authorization**: Pluggable policy engine enabling repo/branch/directory level permissions.
- **Encryption**: Support client-side encryption plugins and server-side encryption settings.
- **Auditability**: Record immutable commit metadata, including optional signed attestations (e.g., Ed25519 signatures).

### 10. Tooling Roadmap
- **Initial CLI Commands**: `init`, `status`, `commit`, `checkout`, `branch`, `diff`, `log`, `fetch`, `gc`.
- **GUI/SDK Plans**: Provide SwiftUI reference client; consider REST/GraphQL façade for non-Swift consumers.
- **Automation**: Build GitHub Actions or scripts for repository maintenance (snapshot verification, GC scheduling).

### 11. Open Questions & Future Enhancements
- **Manifest Encoding**: Plain text newline-delimited format is the permanent choice, prioritizing simplicity and debuggability over encoding optimizations.
- **Repository Isolation**: Operate with standalone repositories and no cross-repository deduplication during the first phase.
- **Distributed Locking**: Accept eventual consistency in metadata services with future improvements deferred until real-world constraints emerge.
- **Language Integration**: Defer non-Swift integration plans (C bindings, OCI APIs) to a later milestone.
- **Observability Defaults**: Focus on proof-of-concept functionality before standardizing metrics or logging schemas.
- **Object Metadata** (future): Optional sidecar `.meta` files (e.g., `objects/a3/f2/hash.meta`) for storing file-level metadata such as creation date, author, content-type, or custom attributes. Deferred to post-POC phase.
- **Sensitive Data Removal** (future): Support for intentional object deletion via tombstone files without rewriting history.
  - Tombstone file format: `objects/{hash[0:2]}/{hash[2:4]}/{hash[4:]}.tomb` (JSON containing deletion reason, timestamp, and operator).
  - When `.dat` object is missing, check for corresponding `.tomb` file to distinguish intentional deletion from storage corruption.
  - `getObject` returns `.objectDeleted` error with tombstone metadata when tombstone is present.
  - `listObjects` can optionally include or exclude tombstoned objects based on caller requirements.
  - Preserves hash chain integrity while enabling compliance requirements (secrets removal, GDPR, etc.).
