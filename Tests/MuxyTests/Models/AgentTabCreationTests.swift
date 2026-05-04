import Foundation
import MuxyShared
import RoostHostdCore
import Testing

@testable import Roost

@MainActor
@Suite("Agent tab creation")
struct AgentTabCreationTests {
    @Test("createAgentTab(.terminal) is identical to createTab")
    func terminalCase() {
        let area = TabArea(projectPath: "/tmp/wt")
        let countBefore = area.tabs.count
        area.createAgentTab(kind: .terminal)
        #expect(area.tabs.count == countBefore + 1)
        let pane = area.activeTab?.content.pane
        #expect(pane?.agentKind == .terminal)
        #expect(pane?.startupCommand == nil)
    }

    @Test("createAgentTab(.claudeCode) sets agentKind + preset command")
    func claudeCase() {
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        let pane = area.activeTab?.content.pane
        #expect(pane?.agentKind == .claudeCode)
        #expect(pane?.activityState == .idle)
        #expect(pane?.startupCommand == "claude --dangerously-skip-permissions")
        #expect(pane?.projectPath == "/tmp/wt")
    }

    @Test("createAgentTab(.codex) cwd is the TabArea projectPath (active worktree)")
    func cwdEqualsWorktreePath() {
        let area = TabArea(projectPath: "/Users/me/repo/wt-feature-x")
        area.createAgentTab(kind: .codex)
        let pane = area.activeTab?.content.pane
        #expect(pane?.projectPath == "/Users/me/repo/wt-feature-x")
        #expect(pane?.startupCommand == "codex --disable apps --dangerously-bypass-approvals-and-sandbox")
    }

    @Test("Claude Code tab default title shows agent name")
    func claudeTabTitle() {
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        #expect(area.activeTab?.title == "Claude Code")
    }

    @Test("configured agent env is applied to pane")
    func configuredEnv() throws {
        let appConfig = RoostConfig(agentPresets: [
            RoostConfigAgentPreset(
                name: "Claude",
                kind: .claudeCode,
                command: "claude",
                env: ["CLAUDE_CONFIG_DIR": ".roost/claude"]
            )
        ])
        let projectConfig = RoostConfig(env: ["GLOBAL": "1", "CLAUDE_CONFIG_DIR": "global"])
        let preset = AgentPresetResolver.preset(
            for: .claudeCode,
            appConfig: appConfig,
            projectConfig: projectConfig
        )
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode, preset: preset)
        #expect(area.activeTab?.content.pane?.env == ["GLOBAL": "1", "CLAUDE_CONFIG_DIR": ".roost/claude"])
    }

    @Test("custom title overrides agent display name")
    func customTitleWins() {
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        let tab = area.activeTab
        tab?.customTitle = "Codex (debug)"
        #expect(tab?.title == "Codex (debug)")
    }

    @Test("AppState createAgentTab records a hostd session")
    func appStateCreateAgentTabRecordsSession() async throws {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: AgentTabWorkspacePersistenceStub()
        )
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id
        let client = RecordingHostdClient()

        appState.createAgentTab(.codex, projectID: projectID, hostdClient: client)

        let records = try await client.waitForRecords()
        #expect(records.count == 1)
        #expect(records.first?.projectID == projectID)
        #expect(records.first?.worktreeID == worktreeID)
        #expect(records.first?.workspacePath == "/tmp/wt")
        #expect(records.first?.agentKind == .codex)
        #expect(records.first?.command == "codex --disable apps --dangerously-bypass-approvals-and-sandbox")
    }

    @Test("AppState createAgentTab records hostd launch environment")
    func appStateCreateAgentTabRecordsHostdLaunchEnvironment() async throws {
        let projectURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-hostd-env-tests")
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let appConfig = RoostConfig(agentPresets: [
            RoostConfigAgentPreset(
                name: "Codex",
                kind: .codex,
                command: "codex",
                env: ["PATH": "/custom/bin", "CUSTOM": "1"]
            )
        ])

        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: projectURL.path)
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: AgentTabWorkspacePersistenceStub(),
            appConfigProvider: { appConfig }
        )
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id
        let client = RecordingHostdClient(ownership: .hostdOwnedProcess)

        appState.createAgentTab(.codex, projectID: projectID, hostdClient: client)

        let requests = try await client.waitForRequests()
        let request = try #require(requests.first)
        let pane = try #require(appState.focusedArea(for: projectID)?.activeTab?.content.pane)
        #expect(request.environment["PATH"] == "/custom/bin")
        #expect(request.environment["CUSTOM"] == "1")
        #expect(request.environment["TERM"] == "xterm-256color")
        #expect(request.environment["COLORTERM"] == "truecolor")
        #expect(request.environment["MUXY_PANE_ID"] == pane.id.uuidString)
        #expect(request.environment["MUXY_PROJECT_ID"] == projectID.uuidString)
        #expect(request.environment["MUXY_WORKTREE_ID"] == worktreeID.uuidString)
        #expect(request.command?.contains("export PATH=/custom/bin") == true)
        #expect(request.command?.contains("export SHELL=") == true)
        #expect(request.command?.contains("export TERM=") == false)
        #expect(request.command?.hasSuffix("; codex") == true)
    }

    @Test("AppState createAgentTab uses configured hostd runtime before client is ready")
    func appStateCreateAgentTabUsesConfiguredRuntimeBeforeClientReady() throws {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: AgentTabWorkspacePersistenceStub(),
            hostdRuntimeOwnership: .hostdOwnedProcess
        )
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id

        appState.createAgentTab(.codex, projectID: projectID, hostdClient: nil)

        let pane = try #require(appState.focusedArea(for: projectID)?.activeTab?.content.pane)
        #expect(pane.hostdRuntimeOwnership == .hostdOwnedProcess)
        if case .failed = pane.hostdAttachState {} else {
            Issue.record("Pane should fail instead of staying in preparing state without a hostd client")
        }
    }

    @Test("AppState createAgentTab uses installed hostd client when environment client is stale")
    func appStateCreateAgentTabUsesInstalledHostdClientWhenEnvironmentClientIsStale() async throws {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: AgentTabWorkspacePersistenceStub(),
            hostdRuntimeOwnership: .hostdOwnedProcess
        )
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id
        let client = RecordingHostdClient(ownership: .hostdOwnedProcess)
        await appState.recordRestoredAgentSessions(hostdClient: client)

        appState.createAgentTab(.codex, projectID: projectID, hostdClient: nil)

        let pane = try #require(appState.focusedArea(for: projectID)?.activeTab?.content.pane)
        let requests = try await client.waitForRequests()
        #expect(requests.map(\.id) == [pane.id])
        #expect(pane.hostdAttachState == .ready)
    }

    @Test("AppState marks hostd-owned agent panes from runtime hint")
    func appStateCreateAgentTabUsesHostdOwnedRuntimeHint() async throws {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: AgentTabWorkspacePersistenceStub()
        )
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id
        let client = RecordingHostdClient(ownership: .hostdOwnedProcess)

        appState.createAgentTab(.codex, projectID: projectID, hostdClient: client)

        let pane = try #require(appState.focusedArea(for: projectID)?.activeTab?.content.pane)
        let records = try await client.waitForRecords()
        #expect(pane.hostdRuntimeOwnership == .hostdOwnedProcess)
        #expect(pane.startupCommand == "codex --disable apps --dangerously-bypass-approvals-and-sandbox")
        #expect(records.first?.command?.contains("export PATH=") == true)
        #expect(records.first?.command?.hasSuffix("; codex --disable apps --dangerously-bypass-approvals-and-sandbox") == true)
    }

    @Test("hostd-owned agent panes wait for session creation before attaching")
    func hostdOwnedAgentPaneWaitsForSessionCreation() async throws {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: AgentTabWorkspacePersistenceStub()
        )
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id
        let client = BlockingHostdClient(ownership: .hostdOwnedProcess)

        appState.createAgentTab(.codex, projectID: projectID, hostdClient: client)

        let pane = try #require(appState.focusedArea(for: projectID)?.activeTab?.content.pane)
        #expect(pane.hostdAttachState == .preparing)

        await client.releaseCreateSession()
        try await waitUntil {
            pane.hostdAttachState == .ready
        }
    }

    @Test("hostd-owned panes created before client readiness are replayed later")
    func hostdOwnedPaneCreatedBeforeClientReadinessIsReplayed() async throws {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: AgentTabWorkspacePersistenceStub(),
            hostdRuntimeOwnership: .hostdOwnedProcess
        )
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id

        appState.createAgentTab(.codex, projectID: projectID, hostdClient: nil)

        let pane = try #require(appState.focusedArea(for: projectID)?.activeTab?.content.pane)
        if case .failed = pane.hostdAttachState {} else {
            Issue.record("Pane should fail while hostd client is unavailable")
        }

        let client = RecordingHostdClient(ownership: .hostdOwnedProcess)
        await appState.recordRestoredAgentSessions(hostdClient: client)

        let requests = try await client.waitForRequests()
        #expect(requests.map(\.id) == [pane.id])
        #expect(pane.hostdAttachState == .ready)
    }

    @Test("hostd-owned restored live panes are attach-ready without recreating")
    func restoredLiveHostdAgentPaneBecomesAttachReady() async throws {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex, hostdRuntimeOwnership: .hostdOwnedProcess)
        let pane = try #require(area.activeTab?.content.pane)
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: AgentTabWorkspacePersistenceStub(),
            hostdRuntimeOwnership: .hostdOwnedProcess
        )
        appState.workspaceRoots[key] = .tabArea(area)
        let client = RecordingHostdClient(
            existingLiveRecords: [
                SessionRecord(
                    id: pane.id,
                    projectID: projectID,
                    worktreeID: worktreeID,
                    workspacePath: "/tmp/wt",
                    agentKind: .codex,
                    command: "codex",
                    createdAt: pane.createdAt,
                    lastState: .running
                ),
            ],
            ownership: .hostdOwnedProcess
        )

        await appState.recordRestoredAgentSessions(hostdClient: client)

        let records = await client.createdRecords()
        #expect(records.isEmpty)
        #expect(pane.hostdAttachState == .ready)
    }

    @Test("hostd-owned restored missing panes are recreated")
    func restoredMissingHostdAgentPaneIsRecreated() async throws {
        let project = Project(name: "Project", path: "/tmp/wt")
        let worktree = Worktree(id: UUID(), name: "default", path: "/tmp/wt", isPrimary: true)
        let paneID = UUID()
        let areaID = UUID()
        let snapshot = WorkspaceSnapshot(
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: worktree.path,
            focusedAreaID: areaID,
            root: .tabArea(TabAreaSnapshot(
                id: areaID,
                projectPath: worktree.path,
                tabs: [
                    TerminalTabSnapshot(
                        paneID: paneID,
                        kind: .terminal,
                        customTitle: nil,
                        colorID: nil,
                        isPinned: false,
                        projectPath: worktree.path,
                        paneTitle: "Codex",
                        agentKind: .codex,
                        startupCommand: "codex",
                        hostdRuntimeOwnership: .hostdOwnedProcess
                    ),
                ],
                activeTabIndex: 0
            ))
        )
        let persistence = AgentTabWorkspacePersistenceStub(snapshots: [snapshot])
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(activeProjectID: project.id),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: persistence,
            hostdRuntimeOwnership: .hostdOwnedProcess
        )
        appState.restoreSelection(projects: [project], worktrees: [project.id: [worktree]])
        let client = RecordingHostdClient(ownership: .hostdOwnedProcess)

        await appState.recordRestoredAgentSessions(hostdClient: client)

        let area = try #require(appState.focusedArea(for: project.id))
        let pane = try #require(area.activeTab?.content.pane)
        let requests = try await client.waitForRequests()
        #expect(requests.map(\.id) == [paneID])
        #expect(pane.id == paneID)
        #expect(pane.lastState == .running)
        #expect(pane.hostdAttachState == .ready)
    }

    @Test("AppState records restored agent panes")
    func appStateRecordsRestoredAgentPanes() async throws {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        let pane = try #require(area.activeTab?.content.pane)
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: AgentTabWorkspacePersistenceStub()
        )
        appState.workspaceRoots[key] = .tabArea(area)
        let client = RecordingHostdClient()

        await appState.recordRestoredAgentSessions(hostdClient: client)

        let records = try await client.waitForRecords()
        #expect(records.map(\.id) == [pane.id])
        #expect(records.first?.agentKind == .codex)
        #expect(records.first?.workspacePath == "/tmp/wt")
    }

    @Test("AppState records restored agent panes with hostd launch environment")
    func appStateRecordsRestoredAgentPanesWithHostdLaunchEnvironment() async throws {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex, hostdRuntimeOwnership: .hostdOwnedProcess)
        let pane = try #require(area.activeTab?.content.pane)
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: AgentTabWorkspacePersistenceStub(),
            hostdRuntimeOwnership: .hostdOwnedProcess
        )
        appState.workspaceRoots[key] = .tabArea(area)
        let client = RecordingHostdClient(ownership: .hostdOwnedProcess)

        await appState.recordRestoredAgentSessions(hostdClient: client)

        let requests = try await client.waitForRequests()
        let request = try #require(requests.first)
        #expect(request.environment["MUXY_PANE_ID"] == pane.id.uuidString)
        #expect(request.environment["MUXY_PROJECT_ID"] == projectID.uuidString)
        #expect(request.environment["MUXY_WORKTREE_ID"] == worktreeID.uuidString)
        #expect(request.environment["PATH"]?.contains("\(NSHomeDirectory())/.local/bin") == true)
        #expect(request.environment["TERM"] == "xterm-256color")
        #expect(request.environment["COLORTERM"] == "truecolor")
        #expect(request.command?.contains("export PATH=") == true)
        #expect(request.command?.contains("export TERM=") == false)
        #expect(request.command?.hasSuffix("; codex --disable apps --dangerously-bypass-approvals-and-sandbox") == true)
    }

    @Test("AppState does not recreate restored live hostd agent panes")
    func appStateSkipsRestoredLiveAgentPanes() async throws {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex, hostdRuntimeOwnership: .hostdOwnedProcess)
        let pane = try #require(area.activeTab?.content.pane)
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: AgentTabWorkspacePersistenceStub(),
            hostdRuntimeOwnership: .hostdOwnedProcess
        )
        appState.workspaceRoots[key] = .tabArea(area)
        let client = RecordingHostdClient(
            existingLiveRecords: [
                SessionRecord(
                    id: pane.id,
                    projectID: projectID,
                    worktreeID: worktreeID,
                    workspacePath: "/tmp/wt",
                    agentKind: .codex,
                    command: "codex",
                    createdAt: pane.createdAt,
                    lastState: .running
                ),
            ],
            ownership: .hostdOwnedProcess
        )

        await appState.recordRestoredAgentSessions(hostdClient: client)

        let records = await client.createdRecords()
        #expect(records.isEmpty)
    }

    @Test("restored agent panes adopt configured hostd runtime")
    func restoredAgentPanesAdoptConfiguredHostdRuntime() throws {
        let project = Project(name: "Project", path: "/tmp/wt")
        let worktree = Worktree(name: "default", path: "/tmp/wt", isPrimary: true)
        let paneID = UUID()
        let areaID = UUID()
        let snapshot = WorkspaceSnapshot(
            projectID: project.id,
            worktreeID: worktree.id,
            worktreePath: worktree.path,
            focusedAreaID: areaID,
            root: .tabArea(TabAreaSnapshot(
                id: areaID,
                projectPath: worktree.path,
                tabs: [
                    TerminalTabSnapshot(
                        paneID: paneID,
                        kind: .terminal,
                        customTitle: nil,
                        colorID: nil,
                        isPinned: false,
                        projectPath: worktree.path,
                        paneTitle: "Codex",
                        agentKind: .codex,
                        startupCommand: "codex",
                        hostdRuntimeOwnership: .appOwnedMetadataOnly
                    ),
                ],
                activeTabIndex: 0
            ))
        )
        let appState = AppState(
            selectionStore: AgentTabSelectionStoreStub(activeProjectID: project.id),
            terminalViews: AgentTabTerminalViewRemovingStub(),
            workspacePersistence: AgentTabWorkspacePersistenceStub(snapshots: [snapshot]),
            hostdRuntimeOwnership: .hostdOwnedProcess
        )

        appState.restoreSelection(projects: [project], worktrees: [project.id: [worktree]])

        let pane = try #require(appState.workspaceRoot(for: project.id)?.allAreas().first?.activeTab?.content.pane)
        #expect(pane.id == paneID)
        #expect(pane.agentKind == .codex)
        #expect(pane.hostdRuntimeOwnership == .hostdOwnedProcess)
    }
}

private actor BlockingHostdClient: RoostHostdClient {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var requests: [HostdCreateSessionRequest] = []
    let runtimeOwnershipHint: HostdRuntimeOwnership?

    init(ownership: HostdRuntimeOwnership) {
        self.runtimeOwnershipHint = ownership
    }

    func runtimeOwnership() async throws -> HostdRuntimeOwnership {
        runtimeOwnershipHint ?? .appOwnedMetadataOnly
    }

    func createSession(_ request: HostdCreateSessionRequest) async throws {
        requests.append(request)
        if !released {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func releaseCreateSession() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func markExited(sessionID: UUID) async throws {}
    func listLiveSessions() async throws -> [SessionRecord] { [] }
    func listAllSessions() async throws -> [SessionRecord] { [] }
    func deleteSession(id: UUID) async throws {}
    func pruneExited() async throws {}
    func markAllRunningExited() async throws {}
}

private actor RecordingHostdClient: RoostHostdClient {
    private var created: [SessionRecord] = []
    private var requests: [HostdCreateSessionRequest] = []
    private let existingLiveRecords: [SessionRecord]
    let runtimeOwnershipHint: HostdRuntimeOwnership?

    init(
        existingLiveRecords: [SessionRecord] = [],
        ownership: HostdRuntimeOwnership = .appOwnedMetadataOnly
    ) {
        self.existingLiveRecords = existingLiveRecords
        self.runtimeOwnershipHint = ownership
    }

    func runtimeOwnership() async throws -> HostdRuntimeOwnership {
        runtimeOwnershipHint ?? .appOwnedMetadataOnly
    }

    func createSession(_ request: HostdCreateSessionRequest) async throws {
        requests.append(request)
        created.append(SessionRecord(
            id: request.id,
            projectID: request.projectID,
            worktreeID: request.worktreeID,
            workspacePath: request.workspacePath,
            agentKind: request.agentKind,
            command: request.command,
            createdAt: request.createdAt,
            lastState: .running
        ))
    }

    func markExited(sessionID: UUID) async throws {}
    func listLiveSessions() async throws -> [SessionRecord] { existingLiveRecords + created }
    func listAllSessions() async throws -> [SessionRecord] { existingLiveRecords + created }
    func deleteSession(id: UUID) async throws {}
    func pruneExited() async throws {}
    func markAllRunningExited() async throws {}

    func createdRecords() -> [SessionRecord] {
        created
    }

    func waitForRequests() async throws -> [HostdCreateSessionRequest] {
        for _ in 0..<200 {
            if !requests.isEmpty { return requests }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return requests
    }

    func waitForRecords() async throws -> [SessionRecord] {
        for _ in 0..<200 {
            if !created.isEmpty { return created }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return created
    }
}

private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
    for _ in 0..<50 {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Condition was not met before timeout")
}

@MainActor
private final class AgentTabSelectionStoreStub: ActiveProjectSelectionStoring {
    private var activeProjectID: UUID?
    private var activeWorktreeIDs: [UUID: UUID] = [:]

    init(activeProjectID: UUID? = nil) {
        self.activeProjectID = activeProjectID
    }

    func loadActiveProjectID() -> UUID? { activeProjectID }
    func saveActiveProjectID(_ id: UUID?) { activeProjectID = id }
    func loadActiveWorktreeIDs() -> [UUID: UUID] { activeWorktreeIDs }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) { activeWorktreeIDs = ids }
}

@MainActor
private final class AgentTabTerminalViewRemovingStub: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private final class AgentTabWorkspacePersistenceStub: WorkspacePersisting {
    private var snapshots: [WorkspaceSnapshot]

    init(snapshots: [WorkspaceSnapshot] = []) {
        self.snapshots = snapshots
    }

    func loadWorkspaces() throws -> [WorkspaceSnapshot] { snapshots }
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws { snapshots = workspaces }
}
