import Foundation
import Testing
import MuxyShared

@testable import Roost

@MainActor
@Suite("RemoteServerDelegate worktrees")
struct RemoteServerDelegateWorktreeTests {
    @Test("jj add worktree defaults empty remote branch to current working copy")
    func jjAddWorktreeDefaultsEmptyBranchToCurrentWorkingCopy() async throws {
        let projectDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("remote-jj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: projectDirectory.appendingPathComponent(".jj"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: projectDirectory) }

        let projectStore = ProjectStore(persistence: RemoteProjectPersistenceStub())
        let worktreeStore = WorktreeStore(
            persistence: RemoteWorktreePersistenceStub(),
            listGitWorktrees: { _ in [] },
            listJjWorkspaces: { _ in [] }
        )
        let project = Project(name: "Repo", path: projectDirectory.path, sortOrder: 0)
        projectStore.add(project)
        worktreeStore.ensurePrimary(for: project)

        let calls = RemoteWorktreeControllerCalls()
        let controller = RemoteRecordingWorktreeController(calls: calls)
        let delegate = RemoteServerDelegate(
            appState: AppState(
                selectionStore: RemoteSelectionStoreStub(),
                terminalViews: RemoteTerminalViewRemovingStub(),
                workspacePersistence: RemoteWorkspacePersistenceStub()
            ),
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            resolver: VcsWorktreeControllerResolver { _ in controller }
        )

        let result = try await delegate.vcsAddWorktree(
            projectID: project.id,
            name: "remote-jj",
            branch: "",
            createBranch: false
        )

        let firstCall = await calls.entries.first
        #expect(firstCall?.ref == "@")
        #expect(firstCall?.createRef == false)
        #expect(result.branch == nil)
        #expect(result.vcsKind == .jj)
    }
}

private final class RemoteRecordingWorktreeController: VcsWorktreeController, @unchecked Sendable {
    let calls: RemoteWorktreeControllerCalls

    init(calls: RemoteWorktreeControllerCalls) {
        self.calls = calls
    }

    func addWorktree(repoPath: String, name: String, path: String, ref: String?, createRef: Bool) async throws {
        await calls.append((repoPath: repoPath, name: name, path: path, ref: ref, createRef: createRef))
    }

    func removeWorktree(repoPath _: String, path _: String, target _: VcsWorktreeRemovalTarget, force _: Bool)
        async throws {}

    func deleteRef(repoPath _: String, name _: String) async throws {}
}

private actor RemoteWorktreeControllerCalls {
    var entries: [(repoPath: String, name: String, path: String, ref: String?, createRef: Bool)] = []
    func append(_ entry: (repoPath: String, name: String, path: String, ref: String?, createRef: Bool)) {
        entries.append(entry)
    }
}

private final class RemoteProjectPersistenceStub: ProjectPersisting {
    private var projects: [Project] = []
    func loadProjects() throws -> [Project] { projects }
    func saveProjects(_ projects: [Project]) throws { self.projects = projects }
}

private final class RemoteWorktreePersistenceStub: WorktreePersisting {
    private var storage: [UUID: [Worktree]] = [:]
    func loadWorktrees(projectID: UUID) throws -> [Worktree] { storage[projectID] ?? [] }
    func saveWorktrees(_ worktrees: [Worktree], projectID: UUID) throws { storage[projectID] = worktrees }
    func removeWorktrees(projectID: UUID) throws { storage.removeValue(forKey: projectID) }
}

private final class RemoteWorkspacePersistenceStub: WorkspacePersisting {
    private var snapshots: [WorkspaceSnapshot] = []
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { snapshots }
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws { snapshots = workspaces }
}

@MainActor
private final class RemoteSelectionStoreStub: ActiveProjectSelectionStoring {
    private var activeProjectID: UUID?
    private var activeWorktreeIDs: [UUID: UUID] = [:]
    func loadActiveProjectID() -> UUID? { activeProjectID }
    func saveActiveProjectID(_ id: UUID?) { activeProjectID = id }
    func loadActiveWorktreeIDs() -> [UUID: UUID] { activeWorktreeIDs }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) { activeWorktreeIDs = ids }
}

@MainActor
private final class RemoteTerminalViewRemovingStub: TerminalViewRemoving {
    func removeView(for _: UUID) {}
    func needsConfirmQuit(for _: UUID) -> Bool { false }
}
