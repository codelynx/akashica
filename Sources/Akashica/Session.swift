import Foundation

/// Session actor (independent, stateful)
public actor AkashicaSession {
    private let repository: AkashicaRepository
    private let storage: StorageAdapter

    /// Changeset this session is tied to (immutable after creation)
    public let changeset: ChangesetRef

    /// Optional branch name (for context, not used in operations)
    public let branch: String?

    /// Is this session read-only?
    public var isReadOnly: Bool { changeset.isReadOnly }

    init(
        repository: AkashicaRepository,
        storage: StorageAdapter,
        changeset: ChangesetRef,
        branch: String? = nil
    ) {
        self.repository = repository
        self.storage = storage
        self.changeset = changeset
        self.branch = branch
    }

    // MARK: - Reading Files

    /// Read file from this session's changeset
    public func readFile(at path: RepositoryPath) async throws -> Data {
        switch changeset {
        case .commit(let commitID):
            return try await readFileFromCommit(commitID, path: path)

        case .workspace(let workspaceID):
            return try await readFileFromWorkspace(workspaceID, path: path)
        }
    }

    /// List directory from this session's changeset
    public func listDirectory(at path: RepositoryPath) async throws -> [DirectoryEntry] {
        switch changeset {
        case .commit(let commitID):
            return try await listDirectoryFromCommit(commitID, path: path)

        case .workspace(let workspaceID):
            return try await listDirectoryFromWorkspace(workspaceID, path: path)
        }
    }

    /// Check if file exists
    public func fileExists(at path: RepositoryPath) async throws -> Bool {
        do {
            _ = try await readFile(at: path)
            return true
        } catch AkashicaError.fileNotFound {
            return false
        }
    }

    // MARK: - Writing Files (workspace only)

    /// Write file to workspace
    /// - Throws: AkashicaError.sessionReadOnly if session is on a commit
    public func writeFile(_ data: Data, to path: RepositoryPath) async throws {
        guard case .workspace(let workspaceID) = changeset else {
            throw AkashicaError.sessionReadOnly
        }

        // Write file to workspace
        try await storage.writeWorkspaceFile(
            workspace: workspaceID,
            path: path,
            data: data
        )

        // Update parent directory manifests
        try await updateWorkspaceManifests(workspace: workspaceID, for: path)
    }

    /// Delete file in workspace
    /// - Throws: AkashicaError.sessionReadOnly if session is on a commit
    public func deleteFile(at path: RepositoryPath) async throws {
        guard case .workspace(let workspaceID) = changeset else {
            throw AkashicaError.sessionReadOnly
        }

        // Try to delete file from workspace (may not exist if it's only in base)
        do {
            try await storage.deleteWorkspaceFile(
                workspace: workspaceID,
                path: path
            )
        } catch {
            // File might not exist in workspace, that's OK if it exists in base
            // The manifest update will handle recording the deletion
        }

        // Update parent directory manifests (records the deletion)
        try await updateWorkspaceManifests(workspace: workspaceID, for: path)
    }

    /// Rename/move file in workspace
    /// - Throws: AkashicaError.sessionReadOnly if session is on a commit
    public func moveFile(from: RepositoryPath, to: RepositoryPath) async throws {
        guard case .workspace = changeset else {
            throw AkashicaError.sessionReadOnly
        }

        // Read source file
        let data = try await readFile(at: from)

        // Check if file content has changed
        // If unchanged, create COW reference
        // For now, simple implementation: just copy
        try await writeFile(data, to: to)
        try await deleteFile(at: from)
    }

    // MARK: - Status & Diff

    /// Get status of workspace
    /// - Throws: AkashicaError.sessionReadOnly if session is on a commit
    public func status() async throws -> WorkspaceStatus {
        guard case .workspace(let workspaceID) = changeset else {
            throw AkashicaError.sessionReadOnly
        }

        var modified: [RepositoryPath] = []
        var added: [RepositoryPath] = []
        var deleted: [RepositoryPath] = []
        var renamed: [(from: RepositoryPath, to: RepositoryPath)] = []

        // Recursively walk workspace tree and compare with base
        try await collectChanges(
            workspace: workspaceID,
            path: RepositoryPath(string: ""),
            modified: &modified,
            added: &added,
            deleted: &deleted,
            renamed: &renamed
        )

        return WorkspaceStatus(
            modified: modified,
            added: added,
            deleted: deleted,
            renamed: renamed
        )
    }

    /// Diff this changeset against another commit
    public func diff(against commit: CommitID) async throws -> [FileChange] {
        // TODO: Implement diff
        return []
    }

    // MARK: - Internal Helpers

    private func readFileFromCommit(_ commitID: CommitID, path: RepositoryPath) async throws -> Data {
        // Import AkashicaCore for manifest parsing
        // For now, inline simple parsing to avoid circular dependency

        // 1. Read commit root manifest
        let rootData = try await storage.readRootManifest(commit: commitID)

        // 2. Traverse directory manifests to find file
        var currentManifestData = rootData
        var currentPath = path.components

        // Traverse down the directory tree
        while !currentPath.isEmpty {
            let component = currentPath.removeFirst()
            let isLastComponent = currentPath.isEmpty

            // Parse current manifest
            let entries = try parseManifest(currentManifestData)

            // Find entry for this component
            guard let entry = entries.first(where: { $0.name == component }) else {
                throw AkashicaError.fileNotFound(path)
            }

            if isLastComponent {
                // This is the file we're looking for
                if entry.isDirectory {
                    throw AkashicaError.fileNotFound(path) // Expected file, got directory
                }
                // 3. Read object by hash
                return try await storage.readObject(hash: ContentHash(value: entry.hash))
            } else {
                // This should be a directory, continue traversing
                if !entry.isDirectory {
                    throw AkashicaError.fileNotFound(path) // Expected directory, got file
                }
                // Read next manifest
                currentManifestData = try await storage.readManifest(hash: ContentHash(value: entry.hash))
            }
        }

        // Empty path (root)
        throw AkashicaError.fileNotFound(path)
    }

    // Simple manifest parsing (inline to avoid dependency issues)
    private func parseManifest(_ data: Data) throws -> [(name: String, hash: String, size: Int64, isDirectory: Bool)] {
        guard let content = String(data: data, encoding: .utf8) else {
            throw AkashicaError.invalidManifest("Invalid encoding")
        }

        return try content
            .split(separator: "\n")
            .filter { !$0.isEmpty }
            .map { line in
                let parts = line.split(separator: ":", maxSplits: 2)
                guard parts.count == 3 else {
                    throw AkashicaError.invalidManifest("Invalid format: \(line)")
                }

                let hash = String(parts[0])
                guard let size = Int64(parts[1]) else {
                    throw AkashicaError.invalidManifest("Invalid size: \(parts[1])")
                }
                let name = String(parts[2])

                let isDirectory = name.hasSuffix("/")
                let cleanName = isDirectory ? String(name.dropLast()) : name

                return (name: cleanName, hash: hash, size: size, isDirectory: isDirectory)
            }
    }

    private func readFileFromWorkspace(_ workspaceID: WorkspaceID, path: RepositoryPath) async throws -> Data {
        // Try to read from workspace first
        if let data = try await storage.readWorkspaceFile(workspace: workspaceID, path: path) {
            return data
        }

        // Check for COW reference
        if let cowRef = try await storage.readCOWReference(workspace: workspaceID, path: path) {
            // Read from base commit using hash
            return try await storage.readObject(hash: cowRef.hash)
        }

        // Check if file was explicitly deleted by looking at parent directory manifest
        if let parent = path.parent {
            if let workspaceManifest = try await storage.readWorkspaceManifest(workspace: workspaceID, path: parent) {
                // Workspace manifest exists for parent directory
                let entries = try parseManifest(workspaceManifest)
                // If file is not in the manifest, it was deleted
                if !entries.contains(where: { $0.name == path.name! }) {
                    throw AkashicaError.fileNotFound(path)
                }
            }
        } else {
            // Root level file - check root manifest
            if let workspaceManifest = try await storage.readWorkspaceManifest(workspace: workspaceID, path: RepositoryPath(string: "")) {
                let entries = try parseManifest(workspaceManifest)
                if !entries.contains(where: { $0.name == path.name! }) {
                    throw AkashicaError.fileNotFound(path)
                }
            }
        }

        // Fall back to base commit
        let metadata = try await storage.readWorkspaceMetadata(workspace: workspaceID)
        return try await readFileFromCommit(metadata.base, path: path)
    }

    private func listDirectoryFromCommit(_ commitID: CommitID, path: RepositoryPath) async throws -> [DirectoryEntry] {
        // Read root manifest
        let rootData = try await storage.readRootManifest(commit: commitID)

        var currentManifestData = rootData
        var currentPath = path.components

        // Traverse to the target directory
        while !currentPath.isEmpty {
            let component = currentPath.removeFirst()

            // Parse current manifest
            let entries = try parseManifest(currentManifestData)

            // Find entry for this component
            guard let entry = entries.first(where: { $0.name == component }) else {
                throw AkashicaError.fileNotFound(path)
            }

            // This should be a directory
            if !entry.isDirectory {
                throw AkashicaError.fileNotFound(path) // Expected directory, got file
            }

            // Read next manifest
            currentManifestData = try await storage.readManifest(hash: ContentHash(value: entry.hash))
        }

        // Parse the target directory manifest
        let entries = try parseManifest(currentManifestData)

        // Convert to DirectoryEntry
        return entries.map { entry in
            DirectoryEntry(
                name: entry.name,
                type: entry.isDirectory ? .directory : .file,
                size: entry.size,
                hash: ContentHash(value: entry.hash)
            )
        }
    }

    private func listDirectoryFromWorkspace(_ workspaceID: WorkspaceID, path: RepositoryPath) async throws -> [DirectoryEntry] {
        // Read workspace manifest (if exists)
        let workspaceManifestData = try await storage.readWorkspaceManifest(workspace: workspaceID, path: path)

        // If workspace manifest exists, it's the complete source of truth
        // (it already inherits base entries when first created, and tracks deletions)
        if let workspaceData = workspaceManifestData {
            let workspaceEntries = try parseManifest(workspaceData)
            return workspaceEntries.map { entry in
                DirectoryEntry(
                    name: entry.name,
                    type: entry.isDirectory ? .directory : .file,
                    size: entry.size,
                    hash: ContentHash(value: entry.hash)
                )
            }.sorted { $0.name < $1.name }
        }

        // No workspace manifest - return base commit entries
        let metadata = try await storage.readWorkspaceMetadata(workspace: workspaceID)
        return try await listDirectoryFromCommit(metadata.base, path: path)
    }

    private func updateWorkspaceManifests(workspace: WorkspaceID, for path: RepositoryPath) async throws {
        // Update manifests from leaf directory to root (bottom-up)
        // For path "asia/japan/tokyo.txt":
        //   1. Update asia/japan/ manifest with tokyo.txt entry
        //   2. Update asia/ manifest with japan/ entry (using new hash from step 1)
        //   3. Update root manifest with asia/ entry (using new hash from step 2)

        let components = path.components
        guard !components.isEmpty else {
            return
        }

        // Compute file hash/size if file exists, nil if deleted
        let fileData = try await storage.readWorkspaceFile(workspace: workspace, path: path)
        var currentHash: String?
        var currentSize: Int64?

        if let data = fileData {
            let fileHash = ContentHash(data: data)
            currentHash = fileHash.value
            currentSize = Int64(data.count)
        } else {
            currentHash = nil
            currentSize = nil
        }

        // Update all parent directories from leaf to root
        for depth in (0..<components.count).reversed() {
            let dirPath = depth == 0 ? RepositoryPath(string: "") : RepositoryPath(components: Array(components[0..<depth]))
            let entryName = components[depth]

            // Update manifest at this directory level
            let (hash, size) = try await updateSingleDirectoryManifest(
                workspace: workspace,
                dirPath: dirPath,
                entryName: entryName,
                isFile: depth == components.count - 1,  // true if this is the immediate parent of the file
                childHash: currentHash,
                childSize: currentSize
            )

            // Store for next level up
            currentHash = hash
            currentSize = size
        }
    }

    /// Update a single directory's manifest with one entry change
    /// Returns the (hash, size) of the updated manifest for parent directory to use
    private func updateSingleDirectoryManifest(
        workspace: WorkspaceID,
        dirPath: RepositoryPath,
        entryName: String,
        isFile: Bool,
        childHash: String?,
        childSize: Int64?
    ) async throws -> (hash: String, size: Int64) {
        // Read current workspace manifest (if exists)
        let existingData = try await storage.readWorkspaceManifest(workspace: workspace, path: dirPath)

        // Parse existing entries
        var entries: [String: (hash: String, size: Int64, isDirectory: Bool)] = [:]
        if let data = existingData {
            let parsed = try parseManifest(data)
            for entry in parsed {
                entries[entry.name] = (hash: entry.hash, size: entry.size, isDirectory: entry.isDirectory)
            }
        } else {
            // No workspace manifest exists yet - inherit all files from base commit
            let metadata = try await storage.readWorkspaceMetadata(workspace: workspace)
            do {
                let baseEntries = try await listDirectoryFromCommit(metadata.base, path: dirPath)
                for entry in baseEntries {
                    entries[entry.name] = (hash: entry.hash.value, size: entry.size, isDirectory: entry.type == .directory)
                }
            } catch {
                // Base directory might not exist, that's OK
            }
        }

        // Update or remove the entry
        if let hash = childHash, let size = childSize {
            // Entry exists (file or directory)
            entries[entryName] = (hash: hash, size: size, isDirectory: !isFile)
        } else {
            // Entry was deleted
            entries.removeValue(forKey: entryName)
        }

        // Build new manifest
        let manifestLines = entries.map { name, info in
            let displayName = info.isDirectory ? "\(name)/" : name
            return "\(info.hash):\(info.size):\(displayName)"
        }.sorted()

        let manifestContent = manifestLines.isEmpty ? "" : manifestLines.joined(separator: "\n")
        let manifestData = manifestContent.data(using: .utf8)!

        // Write manifest to workspace
        try await storage.writeWorkspaceManifest(workspace: workspace, path: dirPath, data: manifestData)

        // Return hash and size for parent directory
        let manifestHash = ContentHash(data: manifestData)
        return (manifestHash.value, Int64(manifestData.count))
    }

    /// Recursively collect changes between workspace and base commit
    private func collectChanges(
        workspace: WorkspaceID,
        path: RepositoryPath,
        modified: inout [RepositoryPath],
        added: inout [RepositoryPath],
        deleted: inout [RepositoryPath],
        renamed: inout [(from: RepositoryPath, to: RepositoryPath)]
    ) async throws {
        // Get workspace manifest (if exists)
        let workspaceManifestData = try await storage.readWorkspaceManifest(workspace: workspace, path: path)

        // Get base commit manifest
        let metadata = try await storage.readWorkspaceMetadata(workspace: workspace)
        let baseEntries: [DirectoryEntry]
        do {
            baseEntries = try await listDirectoryFromCommit(metadata.base, path: path)
        } catch AkashicaError.fileNotFound {
            // Directory doesn't exist in base, all workspace files are added
            if let workspaceData = workspaceManifestData {
                let entries = try parseManifest(workspaceData)
                for entry in entries {
                    let filePath = path.components.isEmpty
                        ? RepositoryPath(string: entry.name)
                        : RepositoryPath(components: path.components + [entry.name])
                    if entry.isDirectory {
                        try await collectChanges(
                            workspace: workspace,
                            path: filePath,
                            modified: &modified,
                            added: &added,
                            deleted: &deleted,
                            renamed: &renamed
                        )
                    } else {
                        added.append(filePath)
                    }
                }
            }
            return
        }

        // Create lookup maps
        var baseMap: [String: DirectoryEntry] = [:]
        for entry in baseEntries {
            baseMap[entry.name] = entry
        }

        var workspaceMap: [String: (hash: String, size: Int64, isDirectory: Bool)] = [:]
        if let workspaceData = workspaceManifestData {
            let entries = try parseManifest(workspaceData)
            for entry in entries {
                workspaceMap[entry.name] = (hash: entry.hash, size: entry.size, isDirectory: entry.isDirectory)
            }
        }

        // Check for modifications, additions, and deletions
        var processedNames = Set<String>()

        // Process workspace entries
        for (name, workspaceEntry) in workspaceMap {
            processedNames.insert(name)
            let filePath = path.components.isEmpty
                ? RepositoryPath(string: name)
                : RepositoryPath(components: path.components + [name])

            if let baseEntry = baseMap[name] {
                // File exists in both - check if modified
                if workspaceEntry.hash != baseEntry.hash.value {
                    if !workspaceEntry.isDirectory {
                        modified.append(filePath)
                    }
                }
                // Recurse into directories
                if workspaceEntry.isDirectory {
                    try await collectChanges(
                        workspace: workspace,
                        path: filePath,
                        modified: &modified,
                        added: &added,
                        deleted: &deleted,
                        renamed: &renamed
                    )
                }
            } else {
                // File exists in workspace but not in base
                // Check if it's a COW reference (potential rename)
                if try await storage.readCOWReference(workspace: workspace, path: filePath) != nil {
                    // This is a renamed file - find original
                    // For now, just mark as added (rename detection is complex)
                    added.append(filePath)
                } else {
                    // New file
                    if workspaceEntry.isDirectory {
                        try await collectChanges(
                            workspace: workspace,
                            path: filePath,
                            modified: &modified,
                            added: &added,
                            deleted: &deleted,
                            renamed: &renamed
                        )
                    } else {
                        added.append(filePath)
                    }
                }
            }
        }

        // Process base entries not in workspace (potential deletions)
        for (name, baseEntry) in baseMap {
            if !processedNames.contains(name) {
                let filePath = path.components.isEmpty
                    ? RepositoryPath(string: name)
                    : RepositoryPath(components: path.components + [name])

                // Only mark as deleted if file existed in workspace manifest but is now gone
                // If workspace manifest doesn't exist, file is unchanged (still in base)
                if let workspaceData = workspaceManifestData {
                    // Workspace manifest exists, so this file should have been in workspaceMap if it still exists
                    if baseEntry.type == .file {
                        deleted.append(filePath)
                    }
                }
                // else: no workspace manifest means no changes, file is still in base (unchanged)
            }
        }
    }
}
