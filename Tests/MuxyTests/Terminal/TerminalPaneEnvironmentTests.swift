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
        #expect(env["COLORTERM"] == "truecolor")
        #expect(env["ROOST_PANE_ID"] == "00000000-0000-0000-0000-000000000001")
        #expect(env["ROOST_PROJECT_ID"] == "00000000-0000-0000-0000-000000000002")
        #expect(env["ROOST_WORKTREE_ID"] == "00000000-0000-0000-0000-000000000003")
        #expect(env["ROOST_SOCKET_PATH"] == env["MUXY_SOCKET_PATH"])
        #expect(env["MUXY_PANE_ID"] == "00000000-0000-0000-0000-000000000001")
        #expect(env["MUXY_PROJECT_ID"] == env["ROOST_PROJECT_ID"])
        #expect(env["MUXY_WORKTREE_ID"] == env["ROOST_WORKTREE_ID"])
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
            configured: ["COLORTERM": "24bit", "TERM": "xterm-ghostty"],
            shellPath: "/Users/me/.local/bin:/usr/bin:/bin",
            shell: "/run/current-system/sw/bin/fish"
        )

        #expect(env["TERM"] == "xterm-ghostty")
        #expect(env["COLORTERM"] == "24bit")
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

    @Test("hostd tmux command leaves terminal type to tmux")
    func hostdTmuxCommandLeavesTerminalTypeToTmux() {
        let command = TerminalPaneEnvironment.hostdLaunchCommand(
            "codex",
            environment: [
                "PATH": "/custom/bin:/usr/bin",
                "SHELL": "/bin/zsh",
                "TERM": "xterm-256color",
            ],
            exportTerm: false
        )

        #expect(command == "export PATH=/custom/bin:/usr/bin; export SHELL=/bin/zsh; codex")
    }

    @Test("hostd attach command configures tmux session before attach")
    func hostdAttachCommandConfiguresTmuxSessionBeforeAttach() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let command = TerminalPaneEnvironment.hostdAttachCommand(sessionID: id, tmuxPath: "tmux")

        #expect(command == [
            "tmux set-option -gq 'terminal-features[100]' xterm-256color:RGB:extkeys",
            "set-option -gq 'terminal-features[101]' xterm-ghostty:RGB:extkeys",
            "set-option -gq 'terminal-features[102]' 'ghostty*:RGB:extkeys'",
            "set-option -gq extended-keys always",
            "set-option -gq extended-keys-format csi-u",
            "set-option -t roost-00000000-0000-0000-0000-000000000123 mouse on",
            "set-option -t roost-00000000-0000-0000-0000-000000000123 status off",
            "set-option -t roost-00000000-0000-0000-0000-000000000123 prefix None",
            "set-option -t roost-00000000-0000-0000-0000-000000000123 prefix2 None",
            ##"bind-key -T root WheelUpPane 'if-shell -F "#{||:#{alternate_on},#{pane_in_mode},#{mouse_any_flag}}" "send-keys -M" "copy-mode -e; send-keys -X -N 1 scroll-up"'"##,
            ##"bind-key -T copy-mode Enter 'if-shell -F "#{selection_present}" "send-keys -X copy-pipe-and-cancel" "send-keys -X cancel; send-keys Enter"'"##,
            ##"bind-key -T copy-mode-vi Enter 'if-shell -F "#{selection_present}" "send-keys -X copy-pipe-and-cancel" "send-keys -X cancel; send-keys Enter"'"##,
            "bind-key -T copy-mode WheelUpPane send-keys -X -N 1 scroll-up",
            "bind-key -T copy-mode WheelDownPane send-keys -X -N 1 scroll-down",
            "bind-key -T copy-mode-vi WheelUpPane send-keys -X -N 1 scroll-up",
            "bind-key -T copy-mode-vi WheelDownPane send-keys -X -N 1 scroll-down",
            "attach-session -t roost-00000000-0000-0000-0000-000000000123",
        ].joined(separator: " \\; "))
    }

    @Test("hostd attach command quotes tmux path")
    func hostdAttachCommandQuotesTmuxPath() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        let command = TerminalPaneEnvironment.hostdAttachCommand(sessionID: id, tmuxPath: "/opt/homebrew/bin/tmux with space")

        #expect(command.hasPrefix(
            "'/opt/homebrew/bin/tmux with space' set-option -gq 'terminal-features[100]' xterm-256color:RGB:extkeys"
        ))
        #expect(command.hasSuffix("attach-session -t roost-00000000-0000-0000-0000-000000000123"))
    }
}
