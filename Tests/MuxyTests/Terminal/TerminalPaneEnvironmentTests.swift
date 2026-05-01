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
}
