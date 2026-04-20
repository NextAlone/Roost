import SwiftUI

@main
struct RoostApp: App {
    var body: some Scene {
        WindowGroup("Roost") {
            RootView()
                .frame(minWidth: 640, minHeight: 400)
                .frame(idealWidth: 960, idealHeight: 600)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Terminal") { launch("shell") }
                    .keyboardShortcut("t", modifiers: .command)
                Button("New Claude Code") { launch("claude") }
                    .keyboardShortcut("1", modifiers: .control)
                Button("New Codex") { launch("codex") }
                    .keyboardShortcut("2", modifiers: .control)
            }
        }
    }

    /// Post a launch request for `agent`. RootView spawns the session in the
    /// currently-selected bucket. One notification per ⌃digit / tab-bar /
    /// empty-state click — the whole app funnels through here.
    private func launch(_ agent: String) {
        NotificationCenter.default.post(
            name: .roostLaunchAgent,
            object: nil,
            userInfo: [RoostNotificationKey.agent: agent]
        )
    }
}
