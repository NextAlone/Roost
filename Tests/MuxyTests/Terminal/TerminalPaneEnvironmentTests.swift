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
}
