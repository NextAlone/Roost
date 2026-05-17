import Foundation
import MuxyShared
import os
import RoostHostdCore
import SwiftUI

private let logger = Logger(subsystem: "app.muxy", category: "AppState")

private struct PendingHostdSession: Sendable {
    let id: UUID
    let projectID: UUID
    let worktreeID: UUID
    let workspacePath: String
    let agentKind: AgentKind
    let command: String?
    let createdAt: Date
    let environment: [String: String]
}

@MainActor
@Observable
final class AppState {
    struct SplitAreaRequest {
        let projectID: UUID
        let areaID: UUID
        let direction: SplitDirection
        let position: SplitPosition
    }

    struct DiffViewerRequest {
        let vcs: VCSTabState
        let filePath: String
        let isStaged: Bool
    }

    struct JjDiffViewerRequest {
        let repoPath: String
        let revset: String
        let filePath: String
    }

    struct AgentTabRequest {
        let kind: AgentKind
        let preset: AgentPreset
        let runtimeOwnership: HostdRuntimeOwnership
    }

    enum Action {
        case selectProject(projectID: UUID, worktreeID: UUID, worktreePath: String)
        case selectWorktree(projectID: UUID, worktreeID: UUID, worktreePath: String)
        case removeProject(projectID: UUID)
        case removeWorktree(
            projectID: UUID,
            worktreeID: UUID,
            replacementWorktreeID: UUID?,
            replacementWorktreePath: String?
        )
        case createTab(projectID: UUID, areaID: UUID?)
        case createTabInDirectory(projectID: UUID, areaID: UUID?, directory: String)
        case createCommandTab(projectID: UUID, areaID: UUID?, name: String, command: String)
        case createVCSTab(projectID: UUID, areaID: UUID?)
        case createAgentTab(projectID: UUID, areaID: UUID?, request: AgentTabRequest)
        case createEditorTab(projectID: UUID, areaID: UUID?, filePath: String, suppressInitialFocus: Bool)
        case createExternalEditorTab(projectID: UUID, areaID: UUID?, filePath: String, command: String)
        case createDiffViewerTab(projectID: UUID, areaID: UUID?, request: DiffViewerRequest)
        case createJjDiffViewerTab(projectID: UUID, areaID: UUID?, request: JjDiffViewerRequest)
        case closeTab(projectID: UUID, areaID: UUID, tabID: UUID)
        case selectTab(projectID: UUID, areaID: UUID, tabID: UUID)
        case selectTabByIndex(projectID: UUID, areaID: UUID?, index: Int)
        case selectNextTab(projectID: UUID)
        case selectPreviousTab(projectID: UUID)
        case splitArea(SplitAreaRequest)
        case closeArea(projectID: UUID, areaID: UUID)
        case focusArea(projectID: UUID, areaID: UUID)
        case focusPaneLeft(projectID: UUID)
        case focusPaneRight(projectID: UUID)
        case focusPaneUp(projectID: UUID)
        case focusPaneDown(projectID: UUID)
        case moveTab(projectID: UUID, request: TabMoveRequest)
        case selectNextProject(projects: [Project], worktrees: [UUID: [Worktree]])
        case selectPreviousProject(projects: [Project], worktrees: [UUID: [Worktree]])
        case navigate(projectID: UUID, worktreeID: UUID, areaID: UUID, tabID: UUID?)
        case applyLayout(projectID: UUID, worktreePath: String, config: LayoutConfig)
        case markPaneSessionExited(paneID: UUID, capturedResumeCommand: String?)
        case reloadAgent(
            paneID: UUID,
            newSessionID: UUID,
            command: String,
            env: [String: String],
            cwd: URL,
            agentBinaryPath: URL?,
            agentBinaryMTime: Date?
        )
        case setBinaryUpdateDetected(paneID: UUID, value: Bool)
        case dismissExitBanner(paneID: UUID)
        case dismissBinaryUpdateBanner(paneID: UUID)
    }

    private let selectionStore: any ActiveProjectSelectionStoring
    private let terminalViews: any TerminalViewRemoving
    private let workspacePersistence: any WorkspacePersisting
    private let appConfigProvider: () -> RoostConfig?
    private let projectConfigProvider: (String) -> RoostConfig?
    private var hostdRuntimeOwnership: HostdRuntimeOwnership
    private var hostdClient: (any RoostHostdClient)?
    private let activityLog: any ActivityLogStoring
    weak var worktreeStore: WorktreeStore?
    var onProjectsEmptied: (([UUID]) -> Void)?

    var activeProjectID: UUID?

    var activeWorktreeID: [UUID: UUID] = [:]

    struct PendingTabClose: Equatable {
        let projectID: UUID
        let areaID: UUID
        let tabID: UUID
    }

    struct PendingLayoutApply: Equatable {
        let projectID: UUID
        let worktreePath: String
        let layoutName: String
    }

    var workspaceRoots: [WorktreeKey: SplitNode] = [:]
    var focusedAreaID: [WorktreeKey: UUID] = [:]
    private(set) var agentActivityRevision = 0
    var pendingLayoutApply: PendingLayoutApply?
    var pendingLayoutApplyBlockedMessage: String?
    var pendingLastTabClose: PendingTabClose?
    var pendingUnsavedEditorTabClose: PendingTabClose?
    var pendingProcessTabClose: PendingTabClose?
    var pendingSaveErrorMessage: String?
    let navigation = NavigationHistory()
    private var focusHistory: [WorktreeKey: [UUID]] = [:]
    private var inFlightReloadPaneIDs: Set<UUID> = []
    private var pendingExitContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    init(
        selectionStore: any ActiveProjectSelectionStoring,
        terminalViews: any TerminalViewRemoving,
        workspacePersistence: any WorkspacePersisting,
        hostdRuntimeOwnership: HostdRuntimeOwnership = .appOwnedMetadataOnly,
        appConfigProvider: @escaping () -> RoostConfig? = { nil },
        projectConfigProvider: @escaping (String) -> RoostConfig? = RoostConfigLoader.load(fromProjectPath:),
        activityLog: any ActivityLogStoring
    ) {
        self.selectionStore = selectionStore
        self.terminalViews = terminalViews
        self.workspacePersistence = workspacePersistence
        self.hostdRuntimeOwnership = hostdRuntimeOwnership
        self.appConfigProvider = appConfigProvider
        self.projectConfigProvider = projectConfigProvider
        self.activityLog = activityLog
    }

    func restoreSelection(projects: [Project], worktrees: [UUID: [Worktree]]) {
        let snapshots: [WorkspaceSnapshot]
        do {
            snapshots = try workspacePersistence.loadWorkspaces()
        } catch {
            logger.error("Failed to load workspaces: \(error)")
            snapshots = []
        }
        let restored = WorkspaceRestorer.restoreAll(
            from: snapshots,
            projects: projects,
            worktrees: worktrees,
            agentRuntimeOwnership: hostdRuntimeOwnership
        )
        for entry in restored {
            workspaceRoots[entry.key] = entry.root
            focusedAreaID[entry.key] = entry.focusedAreaID
        }

        let savedWorktreeIDs = selectionStore.loadActiveWorktreeIDs()
        for project in projects {
            let restoredKeysForProject = restored.map(\.key).filter { $0.projectID == project.id }
            guard !restoredKeysForProject.isEmpty else { continue }
            if let savedWorktreeID = savedWorktreeIDs[project.id],
               restoredKeysForProject.contains(where: { $0.worktreeID == savedWorktreeID })
            {
                activeWorktreeID[project.id] = savedWorktreeID
                continue
            }
            activeWorktreeID[project.id] = restoredKeysForProject[0].worktreeID
        }

        guard let id = selectionStore.loadActiveProjectID(),
              projects.contains(where: { $0.id == id }),
              activeWorktreeID[id] != nil
        else { return }
        activeProjectID = id
        recordCurrentNavigationEntry()
    }

    func saveWorkspaces() {
        let snapshots = WorkspaceRestorer.snapshotAll(
            workspaceRoots: workspaceRoots,
            focusedAreaID: focusedAreaID
        )
        do {
            try workspacePersistence.saveWorkspaces(snapshots)
        } catch {
            logger.error("Failed to save workspaces: \(error)")
        }
    }

    private func saveSelection() {
        selectionStore.saveActiveProjectID(activeProjectID)
        selectionStore.saveActiveWorktreeIDs(activeWorktreeID)
    }

    func activeWorktreeKey(for projectID: UUID) -> WorktreeKey? {
        guard let worktreeID = activeWorktreeID[projectID] else { return nil }
        return WorktreeKey(projectID: projectID, worktreeID: worktreeID)
    }

    func workspaceRoot(for projectID: UUID) -> SplitNode? {
        guard let key = activeWorktreeKey(for: projectID) else { return nil }
        return workspaceRoots[key]
    }

    func focusedAreaID(for projectID: UUID) -> UUID? {
        guard let key = activeWorktreeKey(for: projectID) else { return nil }
        return focusedAreaID[key]
    }

    func selectProject(_ project: Project, worktree: Worktree) {
        dispatch(.selectProject(
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: worktree.path
        ))
    }

    func selectWorktree(projectID: UUID, worktree: Worktree) {
        dispatch(.selectWorktree(
            projectID: projectID,
            worktreeID: worktree.id,
            worktreePath: worktree.path
        ))
    }

    func focusPane(paneID: UUID) {
        for (key, root) in workspaceRoots {
            for area in root.allAreas() {
                for tab in area.tabs {
                    guard let pane = tab.content.pane, pane.id == paneID else { continue }
                    dispatch(.navigate(
                        projectID: key.projectID,
                        worktreeID: key.worktreeID,
                        areaID: area.id,
                        tabID: tab.id
                    ))
                    return
                }
            }
        }
    }

    func focusedArea(for projectID: UUID) -> TabArea? {
        guard let key = activeWorktreeKey(for: projectID),
              let root = workspaceRoots[key],
              let areaID = focusedAreaID[key]
        else { return nil }
        return root.findArea(id: areaID)
    }

    func agentPresetForRouting(_ kind: AgentKind) -> AgentPreset {
        AgentPresetResolver.preset(for: kind, appConfig: appConfigProvider(), projectConfig: nil)
    }

    private func agentPreset(_ kind: AgentKind, projectID: UUID, areaID: UUID?) -> AgentPreset {
        let area = targetArea(projectID: projectID, areaID: areaID)
        let projectConfig = area.flatMap { projectConfigProvider($0.projectPath) }
        return AgentPresetResolver.preset(for: kind, appConfig: appConfigProvider(), projectConfig: projectConfig)
    }

    private func targetArea(projectID: UUID, areaID: UUID?) -> TabArea? {
        guard let key = activeWorktreeKey(for: projectID),
              let root = workspaceRoots[key]
        else { return nil }
        if let areaID {
            return root.findArea(id: areaID)
        }
        guard let targetAreaID = focusedAreaID[key] else { return nil }
        return root.findArea(id: targetAreaID)
    }

    func allAreas(for projectID: UUID) -> [TabArea] {
        guard let key = activeWorktreeKey(for: projectID) else { return [] }
        return workspaceRoots[key]?.allAreas() ?? []
    }

    func allTabs(forKey key: WorktreeKey) -> [TerminalTab] {
        guard let root = workspaceRoots[key] else { return [] }
        return root.allAreas().flatMap(\.tabs)
    }

    var allAgentPanes: [TerminalPaneState] {
        var result: [TerminalPaneState] = []
        for (_, root) in workspaceRoots {
            for pane in root.allPanes where pane.agentKind != .terminal {
                result.append(pane)
            }
        }
        return result
    }

    var agentAttentionPanes: [AwaitingPaneSummary] {
        _ = agentActivityRevision
        var results: [AwaitingPaneSummary] = []
        for (key, root) in workspaceRoots {
            for area in root.allAreas() {
                for tab in area.tabs {
                    guard let pane = tab.content.pane,
                          let attentionKind = AgentAttentionKind(state: pane.activityState, previousState: pane.previousActivityState)
                    else { continue }
                    results.append(AwaitingPaneSummary(
                        id: pane.id,
                        paneID: pane.id,
                        projectID: key.projectID,
                        worktreeID: key.worktreeID,
                        paneTitle: tab.title,
                        projectName: projectName(for: key.projectID) ?? "",
                        workspaceName: workspaceName(for: key) ?? "",
                        attentionKind: attentionKind
                    ))
                }
            }
        }
        return results.sorted { lhs, rhs in
            if lhs.attentionKind != rhs.attentionKind {
                return lhs.attentionKind.sortOrder < rhs.attentionKind.sortOrder
            }
            return lhs.paneTitle < rhs.paneTitle
        }
    }

    var awaitingPanes: [AwaitingPaneSummary] {
        agentAttentionPanes.filter { $0.attentionKind != .done }
    }

    private func projectName(for id: UUID) -> String? {
        nil
    }

    private func workspaceName(for key: WorktreeKey) -> String? {
        worktreeStore?.worktree(projectID: key.projectID, worktreeID: key.worktreeID)?.name
    }

    @discardableResult
    func updateAgentActivity(paneID: UUID, state: AgentActivityState, sourceType: String? = nil) -> Bool {
        for (key, root) in workspaceRoots {
            for area in root.allAreas() {
                for tab in area.tabs {
                    guard let pane = tab.content.pane, pane.id == paneID else { continue }
                    guard pane.activityState != state else { return true }
                    if state == .completed,
                       pane.activityState == .exited
                    {
                        return true
                    }
                    if state == .awaiting,
                       pane.activityState == .exited
                    {
                        return true
                    }
                    let previous = pane.activityState
                    if state == .awaiting {
                        pane.previousActivityState = pane.activityState
                    }
                    pane.activityState = state
                    advanceAgentActivityRevision()
                    worktreeStore?.markActive(
                        projectID: key.projectID,
                        worktreeID: key.worktreeID,
                        at: Date()
                    )
                    activityLog.append(AgentActivityEvent(
                        paneID: pane.id,
                        projectID: key.projectID,
                        worktreeID: key.worktreeID,
                        from: previous,
                        to: state,
                        sourceType: sourceType
                    ))
                    return true
                }
            }
        }
        return false
    }

    @discardableResult
    func clearCompletedAgentActivity(for key: WorktreeKey) -> Bool {
        guard let root = workspaceRoots[key] else { return false }
        var cleared = false
        for area in root.allAreas() {
            for tab in area.tabs {
                guard let pane = tab.content.pane,
                      pane.agentKind != .terminal
                else { continue }
                if pane.acknowledgeUserInteraction() {
                    cleared = true
                }
            }
        }
        if cleared {
            advanceAgentActivityRevision()
        }
        return cleared
    }

    @discardableResult
    func acknowledgeAgentActivity(paneID: UUID) -> Bool {
        guard let pane = pane(forSessionID: paneID) else { return false }
        let acknowledged = pane.acknowledgeUserInteraction()
        if acknowledged {
            advanceAgentActivityRevision()
        }
        return acknowledged
    }

    @discardableResult
    func markPaneSessionExited(paneID: UUID) -> Bool {
        guard let pane = pane(forSessionID: paneID) else { return false }
        let changed = pane.lastState != .exited || pane.activityState != .exited
        pane.lastState = .exited
        pane.activityState = .exited
        if changed {
            advanceAgentActivityRevision()
        }
        let agentKind = pane.agentKind
        let viewSessionID = pane.sessionID
        if agentKind != .terminal, let client = hostdClient {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let response = try await client.waitForSessionExit(id: paneID, timeoutMs: 1000)
                    if !response.didTimeout {
                        self.handleSessionExit(paneID: paneID, sessionID: viewSessionID, lastTail: response.lastTail)
                    }
                } catch {
                    logger.warning("waitForSessionExit on pane exit failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        return true
    }

    func handleSessionExit(paneID: UUID, sessionID: UUID, lastTail: String?) {
        guard let pane = pane(forSessionID: paneID) else { return }
        guard pane.sessionID == sessionID else { return }
        let preset = agentPresetForRouting(pane.agentKind)
        let captured = Self.extractResumeCommand(preset: preset, lastTail: lastTail)
        dispatch(.markPaneSessionExited(
            paneID: paneID,
            capturedResumeCommand: captured
        ))
        if let continuation = pendingExitContinuations.removeValue(forKey: sessionID) {
            continuation.yield(())
            continuation.finish()
        }
    }

    func refreshBinaryUpdateBanner(paneID: UUID) {
        guard let pane = pane(forSessionID: paneID),
              let path = pane.agentBinaryPath,
              let baseline = pane.agentBinaryMTime
        else { return }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path.path)
        let now = (attrs?[.modificationDate] as? Date) ?? baseline
        let updated = now > baseline
        if updated != pane.binaryUpdateDetected {
            dispatch(.setBinaryUpdateDetected(paneID: paneID, value: updated))
        }
    }

    func reloadAgent(paneID: UUID) async {
        logger.notice("reloadAgent ENTRY paneID=\(paneID, privacy: .public)")
        guard !inFlightReloadPaneIDs.contains(paneID) else {
            logger.notice("reloadAgent SKIPPED inFlight paneID=\(paneID, privacy: .public)")
            return
        }
        inFlightReloadPaneIDs.insert(paneID)
        defer { inFlightReloadPaneIDs.remove(paneID) }

        guard let initialPane = pane(forSessionID: paneID) else {
            logger.notice("reloadAgent NO PANE paneID=\(paneID, privacy: .public)")
            return
        }
        let preset = agentPresetForRouting(initialPane.agentKind)

        var capturedTail: String?
        if let client = hostdClient {
            do {
                let probe = try await client.waitForSessionExit(id: paneID, timeoutMs: 1000)
                if !probe.didTimeout {
                    capturedTail = probe.lastTail
                    let preview = (probe.lastTail ?? "").suffix(400)
                    let tailLen = probe.lastTail?.count ?? -1
                    logger.notice("reloadAgent EXITED len=\(tailLen, privacy: .public) tail=\(String(preview), privacy: .public)")
                } else {
                    logger.notice("reloadAgent PROBE TIMED_OUT (still running)")
                }
            } catch {
                logger.warning("reloadAgent probe failed: \(error.localizedDescription, privacy: .public)")
            }
            if capturedTail == nil {
                logger.notice("reloadAgent INTERRUPTING paneID=\(paneID, privacy: .public)")
                capturedTail = await runReloadInterrupt(
                    sessionID: paneID,
                    gracefulExitInput: initialPane.agentKind.gracefulExitInput
                )
            }
        }

        guard let livePane = pane(forSessionID: paneID) else { return }
        var captured: String?
        if let local = livePane.capturedResumeCommand {
            captured = local
        } else if let tail = capturedTail {
            captured = Self.extractResumeCommand(preset: preset, lastTail: tail)
        }
        logger.notice("reloadAgent CAPTURED captured=\(captured ?? "nil", privacy: .public)")
        let newSessionID = UUID()
        let command = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: captured
        )
        let env = livePane.env
        let cwd = livePane.cwd ?? URL(fileURLWithPath: livePane.currentWorkingDirectory ?? "/tmp")
        let binaryPath = AgentBinary.resolvePath(command: command, env: env)
        let mtime = binaryPath.flatMap { url -> Date? in
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return attrs?[.modificationDate] as? Date
        }

        do {
            try await hostdClient?.terminateSession(id: paneID)
        } catch {
            logger.warning("terminateSession failed during reload: \(error.localizedDescription, privacy: .public)")
        }
        terminalViews.removeView(for: paneID)

        dispatch(.reloadAgent(
            paneID: paneID,
            newSessionID: newSessionID,
            command: command,
            env: env,
            cwd: cwd,
            agentBinaryPath: binaryPath,
            agentBinaryMTime: mtime
        ))

        guard let location = paneLocation(paneID: paneID),
              let reloadedPane = pane(forSessionID: paneID),
              let client = hostdClient
        else { return }
        let environment = TerminalPaneEnvironment.build(
            paneID: paneID,
            worktreeKey: location,
            configured: env
        )
        let launchCommand = TerminalPaneEnvironment.hostdLaunchCommand(
            command,
            environment: environment,
            exportTerm: false
        )
        let agentKind = reloadedPane.agentKind
        let workspacePath = reloadedPane.projectPath
        reloadedPane.markHostdAttachPreparing()
        Task { @MainActor [client, paneID, location, agentKind, workspacePath, environment, launchCommand] in
            let cmdLog = launchCommand ?? "nil"
            logger.notice("reloadAgent CREATE pane=\(paneID, privacy: .public) cmd=\(cmdLog, privacy: .public)")
            do {
                try await client.createSession(HostdCreateSessionRequest(
                    id: paneID,
                    projectID: location.projectID,
                    worktreeID: location.worktreeID,
                    workspacePath: workspacePath,
                    agentKind: agentKind,
                    command: launchCommand,
                    environment: environment
                ))
                logger.notice("reloadAgent CREATE OK pane=\(paneID, privacy: .public)")
                self.pane(forSessionID: paneID)?.markHostdAttachReady()
            } catch {
                let errLog = error.localizedDescription
                logger.error("reloadAgent CREATE FAIL pane=\(paneID, privacy: .public) err=\(errLog, privacy: .public)")
                self.pane(forSessionID: paneID)?.markHostdAttachFailed(Self.hostdErrorMessage(error))
            }
        }
    }

    private func runReloadInterrupt(sessionID: UUID, gracefulExitInput: [String]?) async -> String? {
        guard let client = hostdClient else { return nil }

        if let keys = gracefulExitInput {
            if let tail = await waitOrSendKeys(client: client, sessionID: sessionID, keys: keys, timeoutMs: 5000) {
                return tail
            }
        }
        if let tail = await waitOrInterrupt(client: client, sessionID: sessionID, timeoutMs: 3000) {
            return tail
        }
        if let tail = await waitOrInterrupt(client: client, sessionID: sessionID, timeoutMs: 3000) {
            return tail
        }
        do {
            try await client.terminateSession(id: sessionID)
        } catch {
            logger.warning("force terminateSession failed: \(error.localizedDescription, privacy: .public)")
        }
        do {
            let response = try await client.waitForSessionExit(id: sessionID, timeoutMs: 3000)
            if !response.didTimeout { return response.lastTail }
        } catch {
            logger.warning("waitForSessionExit (post-kill) failed: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    private func waitOrSendKeys(
        client: any RoostHostdClient,
        sessionID: UUID,
        keys: [String],
        timeoutMs: Int
    ) async -> String? {
        do {
            try await client.sendTmuxKeys(id: sessionID, keys: keys)
        } catch {
            logger.warning("sendTmuxKeys failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        do {
            let response = try await client.waitForSessionExit(id: sessionID, timeoutMs: timeoutMs)
            if !response.didTimeout { return response.lastTail }
        } catch {
            logger.warning("waitForSessionExit after sendTmuxKeys failed: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    private func waitOrInterrupt(
        client: any RoostHostdClient,
        sessionID: UUID,
        timeoutMs: Int
    ) async -> String? {
        do {
            try await client.interruptSession(id: sessionID)
        } catch {
            logger.warning("interruptSession failed: \(error.localizedDescription, privacy: .public)")
        }
        do {
            let response = try await client.waitForSessionExit(id: sessionID, timeoutMs: timeoutMs)
            if !response.didTimeout { return response.lastTail }
        } catch {
            logger.warning("waitForSessionExit failed: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    func sessionExitStream(for sessionID: UUID) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        pendingExitContinuations[sessionID] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.pendingExitContinuations.removeValue(forKey: sessionID)
            }
        }
        return stream
    }

    private static func extractResumeCommand(preset: AgentPreset, lastTail: String?) -> String? {
        guard let lastTail, let regex = preset.compiledResumeRegex() else { return nil }
        let range = NSRange(lastTail.startIndex..., in: lastTail)
        guard let match = regex.matches(in: lastTail, range: range).last,
              let r = Range(match.range, in: lastTail)
        else { return nil }
        return String(lastTail[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchCapturedResumeCommand(sessionID: UUID, preset: AgentPreset) async -> String? {
        guard let client = hostdClient else { return nil }
        do {
            let sessions = try await client.listAllSessions()
            guard let record = sessions.first(where: { $0.id == sessionID }),
                  let tail = record.lastTail
            else { return nil }
            return Self.extractResumeCommand(preset: preset, lastTail: tail)
        } catch {
            logger.warning("listAllSessions failed during reload: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func splitFocusedArea(direction: SplitDirection, projectID: UUID) {
        guard let area = focusedArea(for: projectID) else { return }
        dispatch(.splitArea(.init(
            projectID: projectID,
            areaID: area.id,
            direction: direction,
            position: .second
        )))
    }

    func closeArea(_ areaID: UUID, projectID: UUID) {
        dispatch(.closeArea(projectID: projectID, areaID: areaID))
    }

    func createTab(projectID: UUID) {
        dispatch(.createTab(projectID: projectID, areaID: nil))
    }

    func createCommandTab(projectID: UUID, shortcut: CommandShortcut) {
        dispatch(.createCommandTab(
            projectID: projectID,
            areaID: nil,
            name: shortcut.displayName,
            command: shortcut.trimmedCommand
        ))
    }

    func createVCSTab(projectID: UUID) {
        dispatch(.createVCSTab(projectID: projectID, areaID: nil))
    }

    func createAgentTab(
        _ kind: AgentKind,
        projectID: UUID,
        areaID: UUID? = nil,
        hostdClient: (any RoostHostdClient)?
    ) {
        let effectiveHostdClient = hostdClient ?? self.hostdClient
        let runtimeOwnership = effectiveHostdClient?.runtimeOwnershipHint ?? hostdRuntimeOwnership
        let preset = agentPreset(kind, projectID: projectID, areaID: areaID)
        dispatch(.createAgentTab(
            projectID: projectID,
            areaID: areaID,
            request: AgentTabRequest(kind: kind, preset: preset, runtimeOwnership: runtimeOwnership)
        ))
        guard let area = focusedArea(for: projectID),
              let tab = area.activeTab,
              let pane = tab.content.pane,
              let worktreeID = activeWorktreeID[projectID]
        else { return }
        guard let effectiveHostdClient else {
            if runtimeOwnership == .hostdOwnedProcess {
                pane.markHostdAttachFailed("Roost hostd is still starting. The session will start when hostd is ready.")
            }
            return
        }
        let paneID = pane.id
        let workspacePath = pane.projectPath
        let agentKind = pane.agentKind
        let environment = TerminalPaneEnvironment.build(
            paneID: paneID,
            worktreeKey: WorktreeKey(projectID: projectID, worktreeID: worktreeID),
            configured: pane.env
        )
        let command = runtimeOwnership == .hostdOwnedProcess
            ? TerminalPaneEnvironment.hostdLaunchCommand(
                pane.startupCommand,
                environment: environment,
                exportTerm: agentKind == .terminal
            )
            : pane.startupCommand
        pane.markHostdAttachPreparing()
        Task { @MainActor [hostdClient = effectiveHostdClient, pane] in
            do {
                try await hostdClient.createSession(HostdCreateSessionRequest(
                    id: paneID,
                    projectID: projectID,
                    worktreeID: worktreeID,
                    workspacePath: workspacePath,
                    agentKind: agentKind,
                    command: command,
                    environment: environment
                ))
                pane.markHostdAttachReady()
            } catch {
                pane.markHostdAttachFailed(Self.hostdErrorMessage(error))
            }
        }
    }

    private static func hostdErrorMessage(_ error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return String(describing: error) }
        return message
    }

    private func markHostdAttachReady(sessionID: UUID) {
        pane(forSessionID: sessionID)?.markHostdAttachReady()
    }

    private func markHostdAttachFailed(sessionID: UUID, error: Error) {
        pane(forSessionID: sessionID)?.markHostdAttachFailed(Self.hostdErrorMessage(error))
    }

    private func markHostdAttachFailed(sessionID: UUID, message: String, lastState: SessionLifecycleState? = nil) {
        guard let pane = pane(forSessionID: sessionID) else { return }
        if let lastState {
            pane.lastState = lastState
        }
        pane.markHostdAttachFailed(message)
    }

    private func pane(forSessionID sessionID: UUID) -> TerminalPaneState? {
        for root in workspaceRoots.values {
            for area in root.allAreas() {
                if let pane = area.tabs.compactMap(\.content.pane).first(where: { $0.id == sessionID }) {
                    return pane
                }
            }
        }
        return nil
    }

    private func paneLocation(paneID: UUID) -> WorktreeKey? {
        for (key, root) in workspaceRoots {
            for area in root.allAreas() {
                if area.tabs.compactMap(\.content.pane).contains(where: { $0.id == paneID }) {
                    return key
                }
            }
        }
        return nil
    }

    private func advanceAgentActivityRevision() {
        agentActivityRevision &+= 1
    }

    func applyHostdRuntimeOwnership(_ ownership: HostdRuntimeOwnership) {
        hostdRuntimeOwnership = ownership
        for root in workspaceRoots.values {
            for area in root.allAreas() {
                for tab in area.tabs {
                    guard let pane = tab.content.pane,
                          pane.agentKind != .terminal
                    else { continue }
                    pane.hostdRuntimeOwnership = ownership
                }
            }
        }
    }

    func recordRestoredAgentSessions(hostdClient: any RoostHostdClient) async {
        self.hostdClient = hostdClient
        let sessions = restoredAgentSessions()
        guard !sessions.isEmpty else { return }
        let liveSessions: [SessionRecord]
        do {
            liveSessions = try await hostdClient.listLiveSessions()
        } catch {
            for session in sessions {
                markHostdAttachFailed(sessionID: session.id, error: error)
            }
            return
        }
        let liveSessionIDs = Set(liveSessions.map(\.id))
        for session in sessions {
            if liveSessionIDs.contains(session.id) {
                markHostdAttachReady(sessionID: session.id)
                continue
            }
            do {
                try await hostdClient.createSession(HostdCreateSessionRequest(
                    id: session.id,
                    projectID: session.projectID,
                    worktreeID: session.worktreeID,
                    workspacePath: session.workspacePath,
                    agentKind: session.agentKind,
                    command: session.command,
                    createdAt: session.createdAt,
                    environment: session.environment
                ))
                markHostdAttachReady(sessionID: session.id)
            } catch {
                markHostdAttachFailed(sessionID: session.id, error: error)
            }
        }
    }

    private func restoredAgentSessions() -> [PendingHostdSession] {
        workspaceRoots.flatMap { key, root in
            root.allAreas().flatMap { area in
                area.tabs.compactMap { tab in
                    guard let pane = tab.content.pane,
                          pane.agentKind != .terminal
                    else { return nil }
                    let environment = TerminalPaneEnvironment.build(
                        paneID: pane.id,
                        worktreeKey: key,
                        configured: pane.env
                    )
                    let command = pane.hostdRuntimeOwnership == .hostdOwnedProcess
                        ? TerminalPaneEnvironment.hostdLaunchCommand(
                            pane.startupCommand,
                            environment: environment,
                            exportTerm: pane.agentKind == .terminal
                        )
                        : pane.startupCommand
                    return PendingHostdSession(
                        id: pane.id,
                        projectID: key.projectID,
                        worktreeID: key.worktreeID,
                        workspacePath: pane.projectPath,
                        agentKind: pane.agentKind,
                        command: command,
                        createdAt: pane.createdAt,
                        environment: environment
                    )
                }
            }
        }
    }

    func openFile(
        _ filePath: String,
        projectID: UUID,
        preserveFocus: Bool = false,
        line: Int? = nil,
        column: Int = 1
    ) {
        let settings = EditorSettings.shared
        if settings.defaultEditor == .terminalCommand {
            let command = settings.externalEditorCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !command.isEmpty {
                openFileInExternalEditor(filePath, projectID: projectID, command: command)
                return
            }
        }
        for area in allAreas(for: projectID) {
            if let tab = area.tabs.first(where: { $0.content.editorState?.filePath == filePath }) {
                dispatch(.selectTab(projectID: projectID, areaID: area.id, tabID: tab.id))
                if let line, let editorState = tab.content.editorState {
                    requestEditorJump(state: editorState, line: line, column: column)
                }
                return
            }
        }
        dispatch(.createEditorTab(projectID: projectID, areaID: nil, filePath: filePath, suppressInitialFocus: preserveFocus))
        if let line {
            for area in allAreas(for: projectID) {
                if let tab = area.tabs.first(where: { $0.content.editorState?.filePath == filePath }),
                   let editorState = tab.content.editorState
                {
                    requestEditorJump(state: editorState, line: line, column: column)
                    break
                }
            }
        }
    }

    private func requestEditorJump(state: EditorTabState, line: Int, column: Int) {
        if state.isMarkdownFile, state.markdownViewMode != .code {
            state.markdownViewMode = .code
        }
        state.pendingJumpLine = line
        state.pendingJumpColumn = max(1, column)
        state.pendingJumpVersion &+= 1
    }

    func handleFileMoved(from oldPath: String, to newPath: String) {
        guard oldPath != newPath else { return }
        let oldPrefix = oldPath + "/"
        for (_, root) in workspaceRoots {
            for area in root.allAreas() {
                for tab in area.tabs {
                    guard let editorState = tab.content.editorState else { continue }
                    let currentPath = editorState.filePath
                    if currentPath == oldPath {
                        editorState.updateFilePath(newPath)
                    } else if currentPath.hasPrefix(oldPrefix) {
                        editorState.updateFilePath(newPath + "/" + String(currentPath.dropFirst(oldPrefix.count)))
                    }
                }
            }
        }
    }

    func openDiffViewer(vcs: VCSTabState, filePath: String, isStaged: Bool, projectID: UUID) {
        for area in allAreas(for: projectID) {
            if let tab = area.tabs.first(where: { tab in
                guard let diff = tab.content.diffViewerState else { return false }
                return diff.filePath == filePath && diff.isStaged == isStaged
            }) {
                dispatch(.selectTab(projectID: projectID, areaID: area.id, tabID: tab.id))
                return
            }
        }
        dispatch(.createDiffViewerTab(
            projectID: projectID,
            areaID: nil,
            request: DiffViewerRequest(vcs: vcs, filePath: filePath, isStaged: isStaged)
        ))
    }

    func openJjDiffViewer(repoPath: String, revset: String, filePath: String, projectID: UUID) {
        for area in allAreas(for: projectID) {
            if let tab = area.tabs.first(where: { tab in
                guard let diff = tab.content.jjDiffViewerState else { return false }
                return diff.repoPath == repoPath
                    && diff.revset == revset
                    && diff.filePath == filePath
            }) {
                dispatch(.selectTab(projectID: projectID, areaID: area.id, tabID: tab.id))
                return
            }
        }
        dispatch(.createJjDiffViewerTab(
            projectID: projectID,
            areaID: nil,
            request: JjDiffViewerRequest(repoPath: repoPath, revset: revset, filePath: filePath)
        ))
    }

    private func openFileInExternalEditor(_ filePath: String, projectID: UUID, command: String) {
        for area in allAreas(for: projectID) {
            if let tab = area.tabs.first(where: { $0.content.pane?.externalEditorFilePath == filePath }) {
                dispatch(.selectTab(projectID: projectID, areaID: area.id, tabID: tab.id))
                return
            }
        }
        dispatch(.createExternalEditorTab(projectID: projectID, areaID: nil, filePath: filePath, command: command))
    }

    func closeTab(_ tabID: UUID, projectID: UUID) {
        guard let area = focusedArea(for: projectID) else { return }
        closeTab(tabID, areaID: area.id, projectID: projectID)
    }

    func closeTab(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        if needsUnsavedEditorConfirmation(tabID: tabID, areaID: areaID, projectID: projectID) {
            pendingUnsavedEditorTabClose = PendingTabClose(projectID: projectID, areaID: areaID, tabID: tabID)
            return
        }
        if needsProcessConfirmation(tabID: tabID, areaID: areaID, projectID: projectID) {
            pendingProcessTabClose = PendingTabClose(projectID: projectID, areaID: areaID, tabID: tabID)
            return
        }
        closeTabAfterConfirmations(tabID, areaID: areaID, projectID: projectID)
    }

    func forceCloseTab(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        clearPendingProcessCloseIfMatching(tabID: tabID, areaID: areaID, projectID: projectID)
        unpinTabIfNeeded(tabID, areaID: areaID, projectID: projectID)
        dispatch(.closeTab(projectID: projectID, areaID: areaID, tabID: tabID))
    }

    func confirmCloseRunningTab() {
        guard let pending = pendingProcessTabClose else { return }
        pendingProcessTabClose = nil
        closeTabAfterConfirmations(pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
    }

    func cancelCloseRunningTab() {
        pendingProcessTabClose = nil
    }

    func confirmCloseUnsavedEditorTab() {
        guard let pending = pendingUnsavedEditorTabClose else { return }
        pendingUnsavedEditorTabClose = nil
        closeTabAfterConfirmations(pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
    }

    func saveAndCloseUnsavedEditorTab() {
        guard let pending = pendingUnsavedEditorTabClose else { return }
        guard let key = activeWorktreeKey(for: pending.projectID),
              let root = workspaceRoots[key],
              let area = root.findArea(id: pending.areaID),
              let tab = area.tabs.first(where: { $0.id == pending.tabID }),
              let editorState = tab.content.editorState
        else {
            pendingUnsavedEditorTabClose = nil
            return
        }
        pendingUnsavedEditorTabClose = nil
        let fileName = editorState.fileName
        Task { [weak self] in
            do {
                try await editorState.saveFileAsync()
                self?.closeTabAfterConfirmations(pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
            } catch {
                self?.pendingSaveErrorMessage = "Failed to save \(fileName): \(error.localizedDescription)"
            }
        }
    }

    func cancelCloseUnsavedEditorTab() {
        pendingUnsavedEditorTabClose = nil
    }

    private func closeTabAfterConfirmations(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        dispatch(.closeTab(projectID: projectID, areaID: areaID, tabID: tabID))
    }

    func confirmCloseLastTab() {
        guard let pending = pendingLastTabClose else { return }
        pendingLastTabClose = nil
        dispatch(.closeTab(projectID: pending.projectID, areaID: pending.areaID, tabID: pending.tabID))
    }

    func cancelCloseLastTab() {
        pendingLastTabClose = nil
    }

    func availableLayouts(for projectID: UUID) -> [LayoutDescriptor] {
        guard let path = activeWorktreePath(for: projectID) else { return [] }
        return LayoutConfig.discover(projectPath: path)
    }

    func requestApplyLayout(projectID: UUID, layoutName: String) {
        pendingLayoutApplyBlockedMessage = nil
        guard let path = activeWorktreePath(for: projectID) else { return }
        if let message = layoutApplyBlockedMessage(projectID: projectID) {
            pendingLayoutApply = nil
            pendingLayoutApplyBlockedMessage = message
            return
        }
        pendingLayoutApply = PendingLayoutApply(
            projectID: projectID,
            worktreePath: path,
            layoutName: layoutName
        )
    }

    func confirmApplyLayout() {
        guard let pending = pendingLayoutApply else { return }
        pendingLayoutApply = nil
        if let message = layoutApplyBlockedMessage(projectID: pending.projectID) {
            pendingLayoutApplyBlockedMessage = message
            return
        }
        guard let config = LayoutConfig.load(projectPath: pending.worktreePath, name: pending.layoutName) else {
            logger.error("Failed to load layout '\(pending.layoutName)' at \(pending.worktreePath)")
            return
        }
        dispatch(.applyLayout(
            projectID: pending.projectID,
            worktreePath: pending.worktreePath,
            config: config
        ))
    }

    func cancelApplyLayout() {
        pendingLayoutApply = nil
    }

    func clearLayoutApplyBlockedMessage() {
        pendingLayoutApplyBlockedMessage = nil
    }

    private func activeWorktreePath(for projectID: UUID) -> String? {
        guard let key = activeWorktreeKey(for: projectID),
              let root = workspaceRoots[key]
        else { return nil }
        return root.allAreas().first?.projectPath
    }

    private func layoutApplyBlockedMessage(projectID: UUID) -> String? {
        guard let key = activeWorktreeKey(for: projectID),
              let root = workspaceRoots[key]
        else { return nil }

        let tabs = root.allAreas().flatMap(\.tabs)
        let unsavedCount = tabs.compactMap(\.content.editorState).filter(\.isModified).count
        if unsavedCount == 1 {
            return "Save or close the unsaved editor tab before applying a layout."
        }
        if unsavedCount > 1 {
            return "Save or close \(unsavedCount) unsaved editor tabs before applying a layout."
        }

        guard TabCloseConfirmationPreferences.confirmRunningProcess else { return nil }
        let runningCount = tabs.compactMap(\.content.pane?.id).filter { terminalViews.needsConfirmQuit(for: $0) }.count
        if runningCount == 1 {
            return "Close the running process or disable running process close confirmation before applying a layout."
        }
        if runningCount > 1 {
            return "Close \(runningCount) running processes or disable running process close confirmation before applying a layout."
        }

        return nil
    }

    private func unpinTabIfNeeded(_ tabID: UUID, areaID: UUID, projectID: UUID) {
        guard let key = activeWorktreeKey(for: projectID),
              let root = workspaceRoots[key],
              let area = root.findArea(id: areaID),
              let tab = area.tabs.first(where: { $0.id == tabID }),
              tab.isPinned
        else { return }
        area.togglePin(tabID)
    }

    func unsavedEditorTabs() -> [EditorTabState] {
        var result: [EditorTabState] = []
        for (_, root) in workspaceRoots {
            for area in root.allAreas() {
                for tab in area.tabs {
                    if let state = tab.content.editorState, state.isModified {
                        result.append(state)
                    }
                }
            }
        }
        return result
    }

    private func needsUnsavedEditorConfirmation(tabID: UUID, areaID: UUID, projectID: UUID) -> Bool {
        guard let key = activeWorktreeKey(for: projectID),
              let root = workspaceRoots[key],
              let area = root.findArea(id: areaID),
              let tab = area.tabs.first(where: { $0.id == tabID }),
              let editorState = tab.content.editorState
        else { return false }
        return editorState.isModified
    }

    private func needsProcessConfirmation(tabID: UUID, areaID: UUID, projectID: UUID) -> Bool {
        guard TabCloseConfirmationPreferences.confirmRunningProcess else { return false }
        guard let key = activeWorktreeKey(for: projectID),
              let root = workspaceRoots[key],
              let area = root.findArea(id: areaID),
              let tab = area.tabs.first(where: { $0.id == tabID }),
              let paneID = tab.content.pane?.id
        else { return false }
        return terminalViews.needsConfirmQuit(for: paneID)
    }

    func selectTabByIndex(_ index: Int, projectID: UUID) {
        dispatch(.selectTabByIndex(projectID: projectID, areaID: nil, index: index))
    }

    func selectNextTab(projectID: UUID) {
        dispatch(.selectNextTab(projectID: projectID))
    }

    func selectPreviousTab(projectID: UUID) {
        dispatch(.selectPreviousTab(projectID: projectID))
    }

    func activeTab(for projectID: UUID) -> TerminalTab? {
        focusedArea(for: projectID)?.activeTab
    }

    func togglePinActiveTab(projectID: UUID) {
        guard let area = focusedArea(for: projectID),
              let tabID = area.activeTabID
        else { return }
        area.togglePin(tabID)
        saveWorkspaces()
    }

    func dispatch(_ action: Action) {
        if case let .focusArea(projectID, areaID) = action,
           let key = activeWorktreeKey(for: projectID),
           focusedAreaID[key] == areaID
        {
            acknowledgeAgentActivity(key: key, areaID: areaID)
            return
        }

        if case let .selectTab(projectID, areaID, tabID) = action,
           let key = activeWorktreeKey(for: projectID),
           let root = workspaceRoots[key],
           let area = root.findArea(id: areaID),
           area.activeTabID == tabID,
           focusedAreaID[key] == areaID
        {
            acknowledgeAgentActivity(key: key, areaID: areaID, tabID: tabID)
            return
        }

        let currentWorkspaceRootSignature = workspaceRootSignature(workspaceRoots)
        var workspace = WorkspaceState(
            activeProjectID: activeProjectID,
            activeWorktreeID: activeWorktreeID,
            workspaceRoots: workspaceRoots,
            focusedAreaID: focusedAreaID,
            focusHistory: focusHistory,
            keepProjectOpenWhenEmpty: true
        )
        let effects = WorkspaceReducer.reduce(action: action, state: &workspace)
        let updatedWorkspaceRootSignature = workspaceRootSignature(workspace.workspaceRoots)
        let workspaceRootsChanged = currentWorkspaceRootSignature != updatedWorkspaceRootSignature
        if activeProjectID != workspace.activeProjectID {
            activeProjectID = workspace.activeProjectID
        }
        if activeWorktreeID != workspace.activeWorktreeID {
            activeWorktreeID = workspace.activeWorktreeID
        }
        if workspaceRootsChanged {
            workspaceRoots = workspace.workspaceRoots
        }
        if focusedAreaID != workspace.focusedAreaID {
            focusedAreaID = workspace.focusedAreaID
        }
        if focusHistory != workspace.focusHistory {
            focusHistory = workspace.focusHistory
        }
        reconcilePendingClosures()

        for paneID in effects.paneIDsToRemove {
            terminalViews.removeView(for: paneID)
        }

        if !effects.projectIDsToRemove.isEmpty {
            onProjectsEmptied?(effects.projectIDsToRemove)
        }

        pruneNavigationHistory()
        recordCurrentNavigationEntry()

        if let activeTabID = NotificationNavigator.activeTabID(appState: self) {
            NotificationStore.shared.markAsRead(tabID: activeTabID)
        }

        if shouldSaveWorkspaceSnapshot(for: action, workspaceRootsChanged: workspaceRootsChanged) {
            saveWorkspaces()
        }
        saveSelection()
    }

    @discardableResult
    private func acknowledgeAgentActivity(key: WorktreeKey, areaID: UUID, tabID: UUID? = nil) -> Bool {
        guard let area = workspaceRoots[key]?.findArea(id: areaID) else { return false }
        let tab: TerminalTab?
        if let tabID {
            tab = area.tabs.first { $0.id == tabID }
        } else {
            tab = area.activeTab
        }
        guard let pane = tab?.content.pane else { return false }
        let acknowledged = pane.acknowledgeUserInteraction()
        if acknowledged {
            advanceAgentActivityRevision()
        }
        return acknowledged
    }

    func goBack() {
        step(delta: -1)
    }

    func goForward() {
        step(delta: 1)
    }

    private func step(delta: Int) {
        while true {
            let targetIndex = navigation.cursor + delta
            guard targetIndex >= 0, targetIndex < navigation.entries.count else { return }
            let target = navigation.entries[targetIndex]
            if applyNavigationEntry(target) {
                navigation.setCursor(targetIndex)
                return
            }
            navigation.removeEntry(at: targetIndex)
        }
    }

    private func applyNavigationEntry(_ entry: NavigationEntry) -> Bool {
        guard navigationEntryIsLive(entry) else { return false }
        navigation.performWithRecordingSuppressed {
            dispatch(.navigate(
                projectID: entry.projectID,
                worktreeID: entry.worktreeID,
                areaID: entry.areaID,
                tabID: entry.tabID
            ))
        }
        return true
    }

    private func currentNavigationEntry() -> NavigationEntry? {
        guard let projectID = activeProjectID,
              let worktreeID = activeWorktreeID[projectID]
        else { return nil }
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        guard let root = workspaceRoots[key],
              let areaID = focusedAreaID[key],
              let area = root.findArea(id: areaID)
        else { return nil }
        return NavigationEntry(
            projectID: projectID,
            worktreeID: worktreeID,
            areaID: areaID,
            tabID: area.activeTabID
        )
    }

    private func recordCurrentNavigationEntry() {
        guard let entry = currentNavigationEntry() else { return }
        navigation.record(entry)
    }

    private func pruneNavigationHistory() {
        let originalCount = navigation.entries.count
        navigation.removeEntries { !navigationEntryIsLive($0) }
        guard navigation.entries.count != originalCount else { return }
        guard let live = currentNavigationEntry(),
              let matchIndex = navigation.entries.lastIndex(of: live)
        else { return }
        navigation.setCursor(matchIndex)
    }

    private func navigationEntryIsLive(_ entry: NavigationEntry) -> Bool {
        let key = WorktreeKey(projectID: entry.projectID, worktreeID: entry.worktreeID)
        guard let root = workspaceRoots[key],
              let area = root.findArea(id: entry.areaID)
        else { return false }
        if let tabID = entry.tabID, !area.tabs.contains(where: { $0.id == tabID }) {
            return false
        }
        return true
    }

    private func workspaceRootSignature(_ roots: [WorktreeKey: SplitNode]) -> [WorktreeKey: UUID] {
        roots.mapValues(\.id)
    }

    private func shouldSaveWorkspaceSnapshot(for action: Action, workspaceRootsChanged: Bool) -> Bool {
        if workspaceRootsChanged { return true }
        switch action {
        case .selectProject,
             .selectWorktree,
             .selectTab,
             .selectTabByIndex,
             .selectNextTab,
             .selectPreviousTab,
             .focusArea,
             .navigate:
            return false
        case .removeProject,
             .removeWorktree,
             .createTab,
             .createTabInDirectory,
             .createCommandTab,
             .createVCSTab,
             .createAgentTab,
             .createEditorTab,
             .createExternalEditorTab,
             .createDiffViewerTab,
             .createJjDiffViewerTab,
             .closeTab,
             .splitArea,
             .closeArea,
             .focusPaneLeft,
             .focusPaneRight,
             .focusPaneUp,
             .focusPaneDown,
             .moveTab,
             .selectNextProject,
             .selectPreviousProject,
             .applyLayout,
             .markPaneSessionExited,
             .reloadAgent,
             .setBinaryUpdateDetected,
             .dismissExitBanner,
             .dismissBinaryUpdateBanner:
            return true
        }
    }

    private func clearPendingProcessCloseIfMatching(tabID: UUID, areaID: UUID, projectID: UUID) {
        guard let pending = pendingProcessTabClose else { return }
        guard pending.projectID == projectID,
              pending.areaID == areaID,
              pending.tabID == tabID
        else { return }
        pendingProcessTabClose = nil
    }

    private func reconcilePendingClosures() {
        if let pending = pendingUnsavedEditorTabClose,
           !tabExists(tabID: pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
        {
            pendingUnsavedEditorTabClose = nil
        }

        if let pending = pendingProcessTabClose,
           !tabExists(tabID: pending.tabID, areaID: pending.areaID, projectID: pending.projectID)
        {
            pendingProcessTabClose = nil
        }
    }

    private func tabExists(tabID: UUID, areaID: UUID, projectID: UUID) -> Bool {
        guard let key = activeWorktreeKey(for: projectID),
              let root = workspaceRoots[key],
              let area = root.findArea(id: areaID)
        else { return false }
        return area.tabs.contains(where: { $0.id == tabID })
    }

    func focusArea(_ areaID: UUID, projectID: UUID) {
        dispatch(.focusArea(projectID: projectID, areaID: areaID))
    }

    func focusPaneLeft(projectID: UUID) {
        dispatch(.focusPaneLeft(projectID: projectID))
    }

    func focusPaneRight(projectID: UUID) {
        dispatch(.focusPaneRight(projectID: projectID))
    }

    func focusPaneUp(projectID: UUID) {
        dispatch(.focusPaneUp(projectID: projectID))
    }

    func focusPaneDown(projectID: UUID) {
        dispatch(.focusPaneDown(projectID: projectID))
    }

    func selectProjectByIndex(_ index: Int, projects: [Project], worktrees: [UUID: [Worktree]]) {
        guard index >= 0, index < projects.count else { return }
        let project = projects[index]
        let list = worktrees[project.id] ?? []
        guard let target = list.first(where: { $0.isPrimary }) ?? list.first else { return }
        selectProject(project, worktree: target)
    }

    func selectNextProject(projects: [Project], worktrees: [UUID: [Worktree]]) {
        dispatch(.selectNextProject(projects: projects, worktrees: worktrees))
    }

    func selectPreviousProject(projects: [Project], worktrees: [UUID: [Worktree]]) {
        dispatch(.selectPreviousProject(projects: projects, worktrees: worktrees))
    }

    func removeProject(_ projectID: UUID) {
        dispatch(.removeProject(projectID: projectID))
    }

    func removeWorktree(projectID: UUID, worktree: Worktree, replacement: Worktree?) {
        guard !worktree.isPrimary else { return }
        dispatch(.removeWorktree(
            projectID: projectID,
            worktreeID: worktree.id,
            replacementWorktreeID: replacement?.id,
            replacementWorktreePath: replacement?.path
        ))
    }
}

enum AgentAttentionKind: Hashable, CaseIterable {
    case needInput
    case wait
    case done

    init?(state: AgentActivityState, previousState: AgentActivityState?) {
        switch state {
        case .awaiting where state.isUrgentAwaiting(previous: previousState):
            self = .needInput
        case .awaiting:
            self = .wait
        case .completed:
            self = .done
        case .running,
             .idle,
             .exited:
            return nil
        }
    }

    var sortOrder: Int {
        switch self {
        case .needInput: 0
        case .wait: 1
        case .done: 2
        }
    }

    var label: String {
        switch self {
        case .needInput: "need input"
        case .wait: "waiting"
        case .done: "done"
        }
    }
}

struct AwaitingPaneSummary: Identifiable, Hashable {
    let id: UUID
    let paneID: UUID
    let projectID: UUID
    let worktreeID: UUID
    let paneTitle: String
    let projectName: String
    let workspaceName: String
    let attentionKind: AgentAttentionKind
}

#if DEBUG
extension AppState {
    func pane(id paneID: UUID) -> TerminalPaneState? {
        pane(forSessionID: paneID)
    }

    func testSetCapturedResume(_ paneID: UUID, captured: String?) {
        guard let pane = pane(forSessionID: paneID) else { return }
        pane.capturedResumeCommand = captured
    }
}
#endif
