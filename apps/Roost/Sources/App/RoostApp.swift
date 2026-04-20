import SwiftUI

@main
struct RoostApp: App {
    @NSApplicationDelegateAdaptor(RoostAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Roost") {
            RootView()
                .frame(minWidth: 640, minHeight: 400)
                .frame(idealWidth: 960, idealHeight: 600)
                .environmentObject(appDelegate)
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
            CommandGroup(after: .appInfo) {
                Button("Roost Status…") {
                    appDelegate.refreshHostdStatus()
                    showStatusAlert(appDelegate.hostdStatus, error: appDelegate.hostdError)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            // ⌘Q stays the default "release" path (preserve agents). A
            // separate ⌘⇧Q tears them down with the grace-period dance.
            CommandGroup(replacing: .appTermination) {
                Button("Quit Roost") {
                    appDelegate.shouldStopAgentsOnQuit = false
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
                Button("Quit & Stop All Agents") {
                    appDelegate.shouldStopAgentsOnQuit = true
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command, .shift])
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

private func showStatusAlert(_ status: HostdStatusSwift?, error: String?) {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Roost hostd"
    if let status {
        alert.informativeText = """
            pid: \(status.pid)
            version: \(status.version)
            uptime: \(status.uptimeSecs)s
            live sessions: \(status.sessionCount)
            socket: \(status.socketPath)
            manifest: \(status.manifestPath)
            """
    } else if let error {
        alert.alertStyle = .warning
        alert.informativeText = "hostd unavailable:\n\(error)"
    } else {
        alert.informativeText = "no status yet"
    }
    alert.addButton(withTitle: "OK")
    alert.runModal()
}
