import Foundation
import MuxyShared
import RoostHostdCore

@testable import Roost

@MainActor
final class AppStateTestRig {
    var terminateCalls: [UUID] = []
    var interruptCalls: [UUID] = []
    var removeViewCalls: [UUID] = []
    var createCalls: [(sessionID: UUID, projectID: UUID, worktreeID: UUID, command: String?, agentKind: AgentKind)] = []
    var markExitedCalls: [UUID] = []
    var deleteCalls: [UUID] = []
    var slowTerminateNanoseconds: UInt64 = 0
    var slowInterruptNanoseconds: UInt64 = 0
    var ownership: HostdRuntimeOwnership = .appOwnedMetadataOnly

    let selectionStore = AppStateTestRigSelectionStore()
    let terminalViews = AppStateTestRigTerminalViewRemoving()
    let workspacePersistence = AppStateTestRigWorkspacePersistence()
    let activityLog = AppStateTestRigActivityLogStore()

    lazy var fakeClient: AppStateTestRigHostdClient = AppStateTestRigHostdClient(rig: self)

    func makeAppState() -> AppState {
        AppState(
            selectionStore: selectionStore,
            terminalViews: terminalViews,
            workspacePersistence: workspacePersistence,
            hostdRuntimeOwnership: ownership,
            appConfigProvider: { nil },
            projectConfigProvider: { _ in nil },
            activityLog: activityLog
        )
    }

    func makeAgentPane(kind: AgentKind, app: AppState) async -> TerminalPaneState {
        await app.recordRestoredAgentSessions(hostdClient: fakeClient)
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: kind, hostdRuntimeOwnership: ownership)
        app.activeProjectID = projectID
        app.activeWorktreeID[projectID] = worktreeID
        app.workspaceRoots[key] = .tabArea(area)
        app.focusedAreaID[key] = area.id
        return area.activeTab!.content.pane!
    }
}

@MainActor
final class AppStateTestRigSelectionStore: ActiveProjectSelectionStoring {
    var savedActiveProjectID: UUID?
    var savedActiveWorktreeIDs: [UUID: UUID] = [:]

    func loadActiveProjectID() -> UUID? { savedActiveProjectID }
    func saveActiveProjectID(_ id: UUID?) { savedActiveProjectID = id }
    func loadActiveWorktreeIDs() -> [UUID: UUID] { savedActiveWorktreeIDs }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) { savedActiveWorktreeIDs = ids }
}

@MainActor
final class AppStateTestRigTerminalViewRemoving: TerminalViewRemoving {
    var removedPaneIDs: [UUID] = []
    var confirmQuitPaneIDs: Set<UUID> = []

    func removeView(for paneID: UUID) {
        removedPaneIDs.append(paneID)
    }

    func needsConfirmQuit(for paneID: UUID) -> Bool {
        confirmQuitPaneIDs.contains(paneID)
    }
}

final class AppStateTestRigWorkspacePersistence: WorkspacePersisting {
    var snapshots: [WorkspaceSnapshot] = []

    func loadWorkspaces() throws -> [WorkspaceSnapshot] { snapshots }
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws { snapshots = workspaces }
}

@MainActor
final class AppStateTestRigActivityLogStore: ActivityLogStoring {
    var appended: [AgentActivityEvent] = []

    func append(_ event: AgentActivityEvent) {
        appended.append(event)
    }
}

final class AppStateTestRigHostdClient: RoostHostdClient, @unchecked Sendable {
    private weak var rig: AppStateTestRig?

    init(rig: AppStateTestRig) {
        self.rig = rig
    }

    var runtimeOwnershipHint: HostdRuntimeOwnership? { nil }

    func runtimeOwnership() async throws -> HostdRuntimeOwnership {
        await MainActor.run { rig?.ownership ?? .appOwnedMetadataOnly }
    }

    func createSession(_ request: HostdCreateSessionRequest) async throws {
        await MainActor.run {
            rig?.createCalls.append((
                sessionID: request.id,
                projectID: request.projectID,
                worktreeID: request.worktreeID,
                command: request.command,
                agentKind: request.agentKind
            ))
        }
    }

    func attachSession(id: UUID) async throws -> HostdAttachSessionResponse {
        let ownership = await MainActor.run { rig?.ownership ?? .appOwnedMetadataOnly }
        throw RoostHostdClientError.unsupportedRuntimeControl(operation: "attach", ownership: ownership)
    }

    func releaseSession(id: UUID) async throws {}

    func terminateSession(id: UUID) async throws {
        let delay = await MainActor.run { rig?.slowTerminateNanoseconds ?? 0 }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        await MainActor.run { rig?.terminateCalls.append(id) }
    }

    func interruptSession(id: UUID) async throws {
        let delay = await MainActor.run { rig?.slowInterruptNanoseconds ?? 0 }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        await MainActor.run { rig?.interruptCalls.append(id) }
    }

    func readSessionOutput(id: UUID, timeout: TimeInterval) async throws -> Data {
        Data()
    }

    func readSessionOutputStream(
        id: UUID,
        after sequence: UInt64?,
        timeout: TimeInterval,
        limit: Int?,
        mode: HostdOutputStreamReadMode
    ) async throws -> HostdOutputRead {
        HostdOutputRead(chunks: [], nextSequence: sequence ?? 0, truncated: false)
    }

    func writeSessionInput(id: UUID, data: Data) async throws {}

    func resizeSession(id: UUID, columns: UInt16, rows: UInt16) async throws {}

    func sendSessionSignal(id: UUID, signal: HostdSessionSignal) async throws {}

    func markExited(sessionID: UUID) async throws {
        await MainActor.run { rig?.markExitedCalls.append(sessionID) }
    }

    func listLiveSessions() async throws -> [SessionRecord] { [] }

    func listAllSessions() async throws -> [SessionRecord] { [] }

    func deleteSession(id: UUID) async throws {
        await MainActor.run { rig?.deleteCalls.append(id) }
    }

    func pruneExited() async throws {}

    func markAllRunningExited() async throws {}
}
