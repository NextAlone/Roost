import Foundation
import MuxyShared
import RoostHostdCore
import Testing

@testable import RoostHostdCore

@Suite("Hostd tmux sessions")
struct HostdTmuxSessionTests {
    @Test("agent sessions launch as detached tmux sessions")
    func agentSessionsLaunchAsDetachedTmuxSessions() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let tmux = RecordingHostdTmuxController(liveSessionIDs: [])
        let registry = HostdProcessRegistry(store: store, tmux: tmux)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        _ = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/roost tmux",
            agentKind: .codex,
            command: "codex --dangerously-bypass-approvals-and-sandbox",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            environment: ["PATH": "/custom/bin", "TERM": "xterm-256color"]
        ))

        let operations = await tmux.operations
        #expect(operations == [
            .launch(
                sessionName: "roost-00000000-0000-0000-0000-000000000123",
                workspacePath: "/tmp/roost tmux",
                command: "codex --dangerously-bypass-approvals-and-sandbox",
                environment: ["PATH": "/custom/bin", "TERM": "xterm-256color"]
            ),
        ])

        let live = try await registry.listLiveSessions()
        #expect(live.map(\.id) == [id])
    }

    @Test("restored live agent records remain live when tmux still has the session")
    func restoredLiveAgentRecordsRemainLiveWhenTmuxStillHasTheSession() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000124")!
        try await store.record(SessionRecord(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/roost",
            agentKind: .codex,
            command: "codex",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastState: .running
        ))
        let tmux = RecordingHostdTmuxController(liveSessionIDs: [id])
        let registry = HostdProcessRegistry(store: store, tmux: tmux)

        let live = try await registry.listLiveSessions()
        let records = try await store.list()

        #expect(live.map(\.id) == [id])
        #expect(records.first?.lastState == .running)
    }

    @Test("stale agent records are marked exited when tmux no longer has the session")
    func staleAgentRecordsAreMarkedExitedWhenTmuxNoLongerHasTheSession() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000125")!
        try await store.record(SessionRecord(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/roost",
            agentKind: .codex,
            command: "codex",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastState: .running
        ))
        let tmux = RecordingHostdTmuxController(liveSessionIDs: [])
        let registry = HostdProcessRegistry(store: store, tmux: tmux)

        let live = try await registry.listLiveSessions()
        let records = try await store.list()

        #expect(live.isEmpty)
        #expect(records.first?.lastState == .exited)
    }

    @Test("terminating an agent session kills its tmux session")
    func terminatingAgentSessionKillsItsTmuxSession() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000126")!
        let tmux = RecordingHostdTmuxController(liveSessionIDs: [])
        let registry = HostdProcessRegistry(store: store, tmux: tmux)

        _ = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/roost",
            agentKind: .codex,
            command: "codex",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        try await registry.terminateSession(id: id)

        let operations = await tmux.operations
        let records = try await store.list()
        #expect(operations.contains(.kill(sessionName: "roost-00000000-0000-0000-0000-000000000126")))
        #expect(records.first?.lastState == .exited)
    }

    @Test("tmux search path includes common user profile locations")
    func tmuxSearchPathIncludesCommonUserProfileLocations() {
        let path = HostdTmuxController.searchPath(environment: [
            "HOME": "/Users/me",
            "PATH": "/usr/bin:/bin",
            "USER": "me",
        ])
        let entries = path.split(separator: ":").map(String.init)

        #expect(entries.contains("/Users/me/.local/bin"))
        #expect(entries.contains("/etc/profiles/per-user/me/bin"))
        #expect(entries.contains("/run/current-system/sw/bin"))
        #expect(entries.contains("/opt/homebrew/bin"))
        #expect(entries.contains("/usr/bin"))
        #expect(entries.count == Set(entries).count)
    }

    @Test("tmux launch arguments configure roost session UI")
    func tmuxLaunchArgumentsConfigureRoostSessionUI() {
        let arguments = HostdTmuxController.launchArguments(
            sessionName: "roost-00000000-0000-0000-0000-000000000123",
            workspacePath: "/tmp/roost tmux",
            command: "codex",
            environment: ["COLORTERM": "truecolor", "TERM": "xterm-256color"]
        )

        #expect(arguments == [
            "new-session", "-d",
            "-s", "roost-00000000-0000-0000-0000-000000000123",
            "-c", "/tmp/roost tmux",
            "-e", "COLORTERM=truecolor",
            "--", "codex",
            ";", "set-option",
            "-gq", "terminal-features[100]", "xterm-256color:RGB",
            ";", "set-option",
            "-gq", "terminal-features[101]", "xterm-ghostty:RGB",
            ";", "set-option",
            "-gq", "terminal-features[102]", "ghostty*:RGB",
            ";", "set-option",
            "-t", "roost-00000000-0000-0000-0000-000000000123",
            "mouse", "on",
            ";", "set-option",
            "-t", "roost-00000000-0000-0000-0000-000000000123",
            "status", "off",
            ";", "set-option",
            "-t", "roost-00000000-0000-0000-0000-000000000123",
            "prefix", "None",
            ";", "set-option",
            "-t", "roost-00000000-0000-0000-0000-000000000123",
            "prefix2", "None",
            ";", "bind-key",
            "-T", "root",
            "WheelUpPane",
            ##"if-shell -F "#{||:#{alternate_on},#{pane_in_mode},#{mouse_any_flag}}" "send-keys -M" "copy-mode -e; send-keys -X -N 1 scroll-up""##,
            ";", "bind-key",
            "-T", "copy-mode",
            "WheelUpPane",
            "send-keys", "-X", "-N", "1", "scroll-up",
            ";", "bind-key",
            "-T", "copy-mode",
            "WheelDownPane",
            "send-keys", "-X", "-N", "1", "scroll-down",
            ";", "bind-key",
            "-T", "copy-mode-vi",
            "WheelUpPane",
            "send-keys", "-X", "-N", "1", "scroll-up",
            ";", "bind-key",
            "-T", "copy-mode-vi",
            "WheelDownPane",
            "send-keys", "-X", "-N", "1", "scroll-down",
        ])
    }

    private func makeTempStoreURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-tests")
            .appendingPathComponent(UUID().uuidString)
        return tmp.appendingPathComponent("sessions.sqlite")
    }
}

private actor RecordingHostdTmuxController: HostdTmuxControlling {
    private var liveSessionNames: Set<String>
    private var recordedOperations: [HostdTmuxOperation] = []

    init(liveSessionIDs: [UUID]) {
        liveSessionNames = Set(liveSessionIDs.map { HostdTmuxSessionName.name(for: $0) })
    }

    var operations: [HostdTmuxOperation] {
        recordedOperations
    }

    func launch(sessionName: String, workspacePath: String, command: String, environment: [String: String]) async throws {
        recordedOperations.append(.launch(
            sessionName: sessionName,
            workspacePath: workspacePath,
            command: command,
            environment: environment
        ))
        liveSessionNames.insert(sessionName)
    }

    func hasSession(named sessionName: String) async -> Bool {
        liveSessionNames.contains(sessionName)
    }

    func killSession(named sessionName: String) async throws {
        recordedOperations.append(.kill(sessionName: sessionName))
        liveSessionNames.remove(sessionName)
    }
}

private enum HostdTmuxOperation: Equatable {
    case launch(sessionName: String, workspacePath: String, command: String, environment: [String: String])
    case kill(sessionName: String)
}
