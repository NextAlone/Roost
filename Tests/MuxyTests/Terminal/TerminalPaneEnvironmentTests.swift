import Foundation
import Testing

@testable import Roost

@MainActor
@Suite("TerminalPaneEnvironment")
struct TerminalPaneEnvironmentTests {
    @Test("injects shell path into terminal panes")
    func injectsShellPath() {
        let env = TerminalPaneEnvironment.build(
            paneID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            worktreeKey: WorktreeKey(
                projectID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                worktreeID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
            ),
            configured: [:],
            shellPath: "/Users/me/.local/bin:/etc/profiles/per-user/me/bin:/usr/bin:/bin",
            shell: "/run/current-system/sw/bin/fish"
        )

        #expect(env["PATH"] == "/Users/me/.local/bin:/etc/profiles/per-user/me/bin:/usr/bin:/bin")
        #expect(env["SHELL"] == "/run/current-system/sw/bin/fish")
        #expect(env["TERM"] == "xterm-256color")
        #expect(env["MUXY_PANE_ID"] == "00000000-0000-0000-0000-000000000001")
    }

    @Test("keeps configured path")
    func keepsConfiguredPath() {
        let env = TerminalPaneEnvironment.build(
            paneID: UUID(),
            worktreeKey: WorktreeKey(projectID: UUID(), worktreeID: UUID()),
            configured: ["PATH": "/custom/bin", "SHELL": "/custom/shell"],
            shellPath: "/Users/me/.local/bin:/usr/bin:/bin",
            shell: "/run/current-system/sw/bin/fish"
        )

        #expect(env["PATH"] == "/custom/bin")
        #expect(env["SHELL"] == "/custom/shell")
    }

    @Test("keeps configured terminal type")
    func keepsConfiguredTerminalType() {
        let env = TerminalPaneEnvironment.build(
            paneID: UUID(),
            worktreeKey: WorktreeKey(projectID: UUID(), worktreeID: UUID()),
            configured: ["TERM": "xterm-ghostty"],
            shellPath: "/Users/me/.local/bin:/usr/bin:/bin",
            shell: "/run/current-system/sw/bin/fish"
        )

        #expect(env["TERM"] == "xterm-ghostty")
    }

    @Test("keeps configured shell environment without resolving defaults")
    func keepsConfiguredShellEnvironmentWithoutResolvingDefaults() {
        func unexpectedPath() -> String {
            Issue.record("PATH resolver should not run when PATH is configured")
            return "/resolved/bin"
        }

        func unexpectedShell() -> String {
            Issue.record("SHELL resolver should not run when SHELL is configured")
            return "/resolved/shell"
        }

        let env = TerminalPaneEnvironment.build(
            paneID: UUID(),
            worktreeKey: WorktreeKey(projectID: UUID(), worktreeID: UUID()),
            configured: ["PATH": "/custom/bin", "SHELL": "/custom/shell"],
            shellPath: unexpectedPath(),
            shell: unexpectedShell()
        )

        #expect(env["PATH"] == "/custom/bin")
        #expect(env["SHELL"] == "/custom/shell")
    }

    @Test("hostd command exports launch path before agent command")
    func hostdCommandExportsLaunchPath() {
        let command = TerminalPaneEnvironment.hostdLaunchCommand(
            "codex",
            environment: [
                "PATH": "/custom/bin:/usr/bin",
                "SHELL": "/bin/zsh",
                "TERM": "xterm-256color",
                "OPENAI_API_KEY": "secret",
            ]
        )

        #expect(command == "export PATH=/custom/bin:/usr/bin; export SHELL=/bin/zsh; export TERM=xterm-256color; codex")
        #expect(command?.contains("secret") == false)
    }

    @Test("hostd command quotes launch values")
    func hostdCommandQuotesLaunchValues() {
        let command = TerminalPaneEnvironment.hostdLaunchCommand(
            "codex",
            environment: [
                "PATH": "/Users/me/bin with space:/usr/bin",
                "SHELL": "/tmp/it's/zsh",
            ]
        )

        #expect(command == "export PATH='/Users/me/bin with space:/usr/bin'; export SHELL='/tmp/it'\\''s/zsh'; codex")
    }

    @Test("hostd attach command uses helper path and session id")
    func hostdAttachCommandUsesHelperPathAndSessionID() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let command = TerminalPaneEnvironment.hostdAttachCommand(
            sessionID: id,
            helperPath: "/tmp/Roost Hostd Attach",
            socketPath: "/tmp/roost attach.sock"
        )

        #expect(command == "'/tmp/Roost Hostd Attach' --session 00000000-0000-0000-0000-000000000123 --socket '/tmp/roost attach.sock'")
    }

    @Test("hostd attach command reports missing helper")
    func hostdAttachCommandReportsMissingHelper() {
        let command = TerminalPaneEnvironment.hostdAttachCommand(sessionID: UUID(), helperPath: nil)

        #expect(command.contains("roost-hostd-attach helper not found"))
        #expect(command.contains("exit 127"))
    }
}
