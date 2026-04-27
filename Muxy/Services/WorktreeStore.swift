import Foundation
import MuxyShared
import os

private let logger = Logger(subsystem: "app.muxy", category: "WorktreeStore")

@MainActor
@Observable
final class WorktreeStore {
    private(set) var worktrees: [UUID: [Worktree]] = [:]
    private var projectIDByPath: [String: UUID] = [:]
    private let persistence: any WorktreePersisting
    private let listGitWorktrees: @Sendable (String) async throws -> [GitWorktreeRecord]
    private let listJjWorkspaces: @Sendable (String) async throws -> [JjWorkspaceEntry]

    init(
        persistence: any WorktreePersisting,
        listGitWorktrees: @escaping @Sendable (String) async throws -> [GitWorktreeRecord] = {
            try await GitWorktreeService.shared.listWorktrees(repoPath: $0)
        },
        listJjWorkspaces: @escaping @Sendable (String) async throws -> [JjWorkspaceEntry] = { repoPath in
            let service = JjWorkspaceService(queue: JjProcessQueue.shared)
            return try await service.list(repoPath: repoPath)
        },
        projects: [Project] = []
    ) {
        self.persistence = persistence
        self.listGitWorktrees = listGitWorktrees
        self.listJjWorkspaces = listJjWorkspaces
        guard !projects.isEmpty else { return }
        loadAll(projects: projects)
    }

    func loadAll(projects: [Project]) {
        for project in projects {
            do {
                var loaded = try persistence.loadWorktrees(projectID: project.id)
                if !loaded.contains(where: \.isPrimary) {
                    loaded.insert(makePrimary(for: project), at: 0)
                    try? persistence.saveWorktrees(loaded, projectID: project.id)
                }
                setWorktrees(sortPrimaryFirst(loaded), for: project.id)
            } catch {
                logger.error("Failed to load worktrees for project \(project.id): \(error)")
                setWorktrees([makePrimary(for: project)], for: project.id)
                save(projectID: project.id)
            }
        }
    }

    func ensurePrimary(for project: Project) {
        var list = worktrees[project.id] ?? []
        if list.contains(where: \.isPrimary) { return }
        list.insert(makePrimary(for: project), at: 0)
        setWorktrees(sortPrimaryFirst(list), for: project.id)
        save(projectID: project.id)
    }

    func list(for projectID: UUID) -> [Worktree] {
        worktrees[projectID] ?? []
    }

    func projectID(forWorktreePath path: String) -> UUID? {
        projectIDByPath[path]
    }

    func primary(for projectID: UUID) -> Worktree? {
        list(for: projectID).first(where: { $0.isPrimary })
    }

    func worktree(projectID: UUID, worktreeID: UUID) -> Worktree? {
        list(for: projectID).first(where: { $0.id == worktreeID })
    }

    func preferred(for projectID: UUID, matching preferredID: UUID?) -> Worktree? {
        let list = list(for: projectID)
        return list.first(where: { $0.id == preferredID })
            ?? list.first(where: { $0.isPrimary })
            ?? list.first
    }

    enum ImportExternalJjWorkspaceError: Error, Sendable {
        case pathDoesNotExist(String)
        case pathNotJjWorkspace(String)
        case duplicateName(String)
        case duplicatePath(String)
    }

    func importExternalJjWorkspace(
        name: String,
        path: String,
        into projectID: UUID
    ) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ImportExternalJjWorkspaceError.pathDoesNotExist(path)
        }
        let jjMarker = (path as NSString).appendingPathComponent(".jj")
        guard FileManager.default.fileExists(atPath: jjMarker) else {
            throw ImportExternalJjWorkspaceError.pathNotJjWorkspace(path)
        }
        let existing = list(for: projectID)
        if existing.contains(where: { $0.name == name || $0.jjWorkspaceName == name }) {
            throw ImportExternalJjWorkspaceError.duplicateName(name)
        }
        let canonical = Self.canonicalPath(path)
        if existing.contains(where: { Self.canonicalPath($0.path) == canonical }) {
            throw ImportExternalJjWorkspaceError.duplicatePath(path)
        }
        let worktree = Worktree(
            name: name,
            path: path,
            source: .external,
            isPrimary: false,
            vcsKind: .jj,
            jjWorkspaceName: name
        )
        add(worktree, to: projectID)
        var remaining = untrackedJjWorkspaceNames[projectID] ?? []
        remaining.removeAll { $0 == name }
        untrackedJjWorkspaceNames[projectID] = remaining
    }

    func add(_ worktree: Worktree, to projectID: UUID) {
        var list = worktrees[projectID] ?? []
        list.append(worktree)
        setWorktrees(sortPrimaryFirst(list), for: projectID)
        save(projectID: projectID)
    }

    func remove(worktreeID: UUID, from projectID: UUID) {
        guard var list = worktrees[projectID] else { return }
        list.removeAll { $0.id == worktreeID && $0.canBeRemoved }
        setWorktrees(list, for: projectID)
        save(projectID: projectID)
    }

    func refreshFromGit(project: Project) async throws -> [Worktree] {
        ensurePrimary(for: project)
        let records = try await listGitWorktrees(project.path).filter { !$0.isBare && !$0.isPrunable }
        var list = worktrees[project.id] ?? []
        let projectKey = Self.canonicalPath(project.path)
        let recordKeys = Set(records.map { Self.canonicalPath($0.path) })

        if let primaryIndex = list.firstIndex(where: \.isPrimary) {
            list[primaryIndex].path = project.path
            list[primaryIndex].name = project.name
        } else {
            list.insert(makePrimary(for: project), at: 0)
        }

        var existingByKey: [String: Worktree] = [:]
        for worktree in list {
            let key = Self.canonicalPath(worktree.path)
            if let existing = existingByKey[key] {
                if worktree.isPrimary, !existing.isPrimary {
                    existingByKey[key] = worktree
                }
            } else {
                existingByKey[key] = worktree
            }
        }

        for record in records {
            let recordKey = Self.canonicalPath(record.path)
            if recordKey == projectKey {
                if let primaryIndex = list.firstIndex(where: \.isPrimary) {
                    list[primaryIndex].branch = record.branch
                }
                continue
            }

            if let existing = existingByKey[recordKey],
               let index = list.firstIndex(where: { $0.id == existing.id })
            {
                list[index].branch = record.branch
                if list[index].isPrimary {
                    list[index].name = project.name
                    list[index].path = project.path
                }
                continue
            }

            list.append(Worktree(
                name: defaultName(for: record),
                path: record.path,
                branch: record.branch,
                source: .external,
                isPrimary: false
            ))
        }

        let sorted = sortPrimaryFirst(list.filter {
            !$0.isExternallyManaged || recordKeys.contains(Self.canonicalPath($0.path))
        })
        setWorktrees(sorted, for: project.id)
        save(projectID: project.id)
        return sorted
    }

    func refreshJj(project: Project) async throws -> [Worktree] {
        ensurePrimary(for: project)
        let entries = try await listJjWorkspaces(project.path)
        let entriesByName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })

        var list = worktrees[project.id] ?? []
        for index in list.indices {
            let name = list[index].isPrimary ? "default" : list[index].name
            if let entry = entriesByName[name] {
                list[index].currentChangeId = entry.workingCopy.full
            }
        }
        list = list.filter { worktree in
            if worktree.isPrimary { return true }
            if worktree.source == .external { return true }
            return entriesByName[worktree.name] != nil
        }

        let trackedNames = Set(list.map { $0.isPrimary ? "default" : $0.name })
        let untracked = entries
            .map(\.name)
            .filter { !trackedNames.contains($0) }
        untrackedJjWorkspaceNames[project.id] = untracked

        let sorted = sortPrimaryFirst(list)
        setWorktrees(sorted, for: project.id)
        save(projectID: project.id)
        return sorted
    }

    private(set) var untrackedJjWorkspaceNames: [UUID: [String]] = [:]

    func untrackedJjWorkspaces(for projectID: UUID) -> [String] {
        untrackedJjWorkspaceNames[projectID] ?? []
    }

    func refresh(project: Project) async throws -> [Worktree] {
        ensurePrimary(for: project)
        let kind = primary(for: project.id)?.vcsKind ?? .default
        switch kind {
        case .git:
            return try await refreshFromGit(project: project)
        case .jj:
            return try await refreshJj(project: project)
        }
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func cleanupOnDisk(
        worktree: Worktree,
        repoPath: String
    ) async {
        guard worktree.canBeRemoved else { return }
        let controller = VcsWorktreeControllerFactory.controller(for: worktree.vcsKind)
        do {
            let target: VcsWorktreeRemovalTarget = worktree.jjWorkspaceName.map { .identified($0) } ?? .orphan
            try await controller.removeWorktree(
                repoPath: repoPath,
                path: worktree.path,
                target: target,
                force: true
            )
        } catch {
            logger.error("Failed to remove worktree at \(worktree.path): \(error)")
        }

        if worktree.ownsBranch,
           let branch = worktree.branch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !branch.isEmpty
        {
            do {
                try await controller.deleteRef(repoPath: repoPath, name: branch)
            } catch {
                logger.error("Failed to delete ref \(branch) for worktree \(worktree.path): \(error)")
            }
        }

        try? FileManager.default.removeItem(atPath: worktree.path)
        removeParentDirectoryIfEmpty(for: worktree.path)
    }

    static func cleanupOnDisk(for project: Project, knownWorktrees: [Worktree]) async {
        let secondaryWorktrees = knownWorktrees.filter(\.canBeRemoved)
        for worktree in secondaryWorktrees {
            await cleanupOnDisk(worktree: worktree, repoPath: project.path)
        }

        let primaryKind = knownWorktrees.first(where: \.isPrimary)?.vcsKind ?? .default
        let controller = VcsWorktreeControllerFactory.controller(for: primaryKind)

        let root = MuxyFileStorage.worktreeRoot(forProjectID: project.id)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let children = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for child in children {
            let childPath = root.appendingPathComponent(child).path
            try? await controller.removeWorktree(
                repoPath: project.path,
                path: childPath,
                target: .orphan,
                force: true
            )
            try? FileManager.default.removeItem(atPath: childPath)
        }
        try? FileManager.default.removeItem(at: root)
    }

    private static func removeParentDirectoryIfEmpty(for path: String) {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        let children = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        guard children.isEmpty else { return }
        try? FileManager.default.removeItem(at: parent)
    }

    func rename(worktreeID: UUID, in projectID: UUID, to newName: String) {
        guard var list = worktrees[projectID],
              let index = list.firstIndex(where: { $0.id == worktreeID })
        else { return }
        list[index].name = newName
        setWorktrees(list, for: projectID)
        save(projectID: projectID)
    }

    func updateBranch(worktreeID: UUID, in projectID: UUID, branch: String?) {
        guard var list = worktrees[projectID],
              let index = list.firstIndex(where: { $0.id == worktreeID })
        else { return }
        list[index].branch = branch
        setWorktrees(list, for: projectID)
        save(projectID: projectID)
    }

    func removeProject(_ projectID: UUID) {
        if let existing = worktrees[projectID] {
            for worktree in existing where projectIDByPath[worktree.path] == projectID {
                projectIDByPath.removeValue(forKey: worktree.path)
            }
        }
        worktrees.removeValue(forKey: projectID)
        do {
            try persistence.removeWorktrees(projectID: projectID)
        } catch {
            logger.error("Failed to remove worktrees file for project \(projectID): \(error)")
        }
    }

    private func setWorktrees(_ list: [Worktree], for projectID: UUID) {
        if let previous = worktrees[projectID] {
            for worktree in previous where projectIDByPath[worktree.path] == projectID {
                projectIDByPath.removeValue(forKey: worktree.path)
            }
        }
        for worktree in list {
            projectIDByPath[worktree.path] = projectID
        }
        worktrees[projectID] = list
    }

    private func makePrimary(for project: Project) -> Worktree {
        Worktree(
            name: project.name,
            path: project.path,
            branch: nil,
            source: .muxy,
            isPrimary: true,
            vcsKind: VcsKindDetector.detect(at: project.path)
        )
    }

    private func sortPrimaryFirst(_ list: [Worktree]) -> [Worktree] {
        let primary = list.filter(\.isPrimary)
        let others = list.filter { !$0.isPrimary }.sorted { $0.createdAt < $1.createdAt }
        return primary + others
    }

    private func save(projectID: UUID) {
        guard let list = worktrees[projectID] else { return }
        do {
            try persistence.saveWorktrees(list, projectID: projectID)
        } catch {
            logger.error("Failed to save worktrees for project \(projectID): \(error)")
        }
    }

    private func defaultName(for record: GitWorktreeRecord) -> String {
        if let branch = record.branch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !branch.isEmpty
        {
            return branch
        }
        return URL(fileURLWithPath: record.path).lastPathComponent
    }
}
