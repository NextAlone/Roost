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
        #expect(pane?.startupCommand == "claude")
        #expect(pane?.projectPath == "/tmp/wt")
    }

    @Test("createAgentTab(.codex) cwd is the TabArea projectPath (active worktree)")
    func cwdEqualsWorktreePath() {
        let area = TabArea(projectPath: "/Users/me/repo/wt-feature-x")
        area.createAgentTab(kind: .codex)
        let pane = area.activeTab?.content.pane
        #expect(pane?.projectPath == "/Users/me/repo/wt-feature-x")
        #expect(pane?.startupCommand == "codex")
    }

    @Test("Claude Code tab default title shows agent name")
    func claudeTabTitle() {
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        #expect(area.activeTab?.title == "Claude Code")
    }

    @Test("configured agent env is applied to pane")
    func configuredEnv() throws {
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-agent-env-tests")
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: project) }
        let roostDir = project.appendingPathComponent(".roost")
        try FileManager.default.createDirectory(at: roostDir, withIntermediateDirectories: true)
        try Data("""
        {
          "schemaVersion": 1,
          "env": { "GLOBAL": "1", "CLAUDE_CONFIG_DIR": "global" },
          "agentPresets": [
            {
              "name": "Claude",
              "kind": "claudeCode",
              "command": "claude",
              "env": { "CLAUDE_CONFIG_DIR": ".roost/claude" }
            }
          ]
        }
        """.utf8).write(to: roostDir.appendingPathComponent("config.json"))

        let area = TabArea(projectPath: project.path)
        area.createAgentTab(kind: .claudeCode)
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
        #expect(records.first?.command == "codex")
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
}

private actor RecordingHostdClient: RoostHostdClient {
    private var created: [SessionRecord] = []

    func runtimeOwnership() async throws -> HostdRuntimeOwnership {
        .appOwnedMetadataOnly
    }

    func createSession(_ request: HostdCreateSessionRequest) async throws {
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
    func listLiveSessions() async throws -> [SessionRecord] { created }
    func listAllSessions() async throws -> [SessionRecord] { created }
    func deleteSession(id: UUID) async throws {}
    func pruneExited() async throws {}
    func markAllRunningExited() async throws {}

    func waitForRecords() async throws -> [SessionRecord] {
        for _ in 0..<20 {
            if !created.isEmpty { return created }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return created
    }
}

@MainActor
private final class AgentTabSelectionStoreStub: ActiveProjectSelectionStoring {
    private var activeProjectID: UUID?
    private var activeWorktreeIDs: [UUID: UUID] = [:]
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
    private var snapshots: [WorkspaceSnapshot] = []
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { snapshots }
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws { snapshots = workspaces }
}
