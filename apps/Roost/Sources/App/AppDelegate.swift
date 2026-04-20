import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted by `RoostAppDelegate` once after launch when hostd reports
    /// non-zero live sessions to restore. RootView listens to import them
    /// as tabs.
    static let roostRestoredSessionsReady =
        Notification.Name("sh.roost.app.restoredSessionsReady")
}

/// Adopt the running hostd (or spawn one) at launch, and route ⌘Q through a
/// notification-style shutdown so AppKit doesn't SIGKILL the process before
/// hostd's grace period finishes.
final class RoostAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// Latest hostd snapshot, polled lazily by views that want it (About,
    /// menu badge). Refreshed on-demand from `refreshHostdStatus()`.
    @Published private(set) var hostdStatus: HostdStatusSwift?
    @Published private(set) var hostdError: String?

    /// Live sessions discovered on the running hostd at app launch. Empty
    /// when the daemon was just spawned. RootView consumes this once via
    /// `consumeRestoredSessions()` and turns each into a `LaunchedSession`
    /// tab.
    private(set) var pendingRestoredSessions: [LiveSessionRowSwift] = []

    /// True when the user picked "Quit & stop all agents". Determines which
    /// shutdown mode `applicationShouldTerminate` uses.
    var shouldStopAgentsOnQuit: Bool = false

    /// Hard cap on how long AppKit waits for our `applicationShouldTerminate`
    /// reply. Hostd's own grace is 5s SIGTERM + 1s SIGKILL → 6s ceiling.
    private let terminateReplyTimeoutMs: UInt64 = 6_000

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshHostdStatus()
    }

    func refreshHostdStatus() {
        // First call lazily spawns hostd via roost-client's ensure_hostd.
        // 2s timeout lives inside the bridge call (HELLO_TIMEOUT).
        do {
            let status = try RoostBridge.hostdStatus()
            hostdStatus = status
            hostdError = nil
            NSLog("[Roost] hostd adopted: pid=%u version=%@ sessions=%u",
                  status.pid, status.version, status.sessionCount)

            // Populate the restore queue if the adopted daemon has live
            // sessions. RootView calls consumeRestoredSessions() once on
            // appear to pick these up.
            if status.sessionCount > 0 {
                do {
                    let live = try RoostBridge.listLiveSessions()
                    pendingRestoredSessions = live
                    NSLog("[Roost] %d live session(s) queued for restore",
                          live.count)
                    NotificationCenter.default.post(
                        name: .roostRestoredSessionsReady,
                        object: nil
                    )
                } catch {
                    NSLog("[Roost] listLiveSessions failed: %@",
                          String(describing: error))
                }
            }
        } catch let err as RustString {
            let msg = err.toString()
            hostdError = msg
            NSLog("[Roost] hostd adopt failed: %@", msg)
        } catch {
            let msg = String(describing: error)
            hostdError = msg
            NSLog("[Roost] hostd adopt failed: %@", msg)
        }
    }

    /// Take the restore queue once. Subsequent calls return an empty array.
    func consumeRestoredSessions() -> [LiveSessionRowSwift] {
        let snapshot = pendingRestoredSessions
        pendingRestoredSessions = []
        return snapshot
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let mode: HostdShutdownMode = shouldStopAgentsOnQuit ? .stop : .release
        NSLog("[Roost] applicationShouldTerminate mode=%@", mode.rawValue)

        // Release path: nothing to wait for. Fire and reply true immediately.
        if mode == .release {
            do {
                _ = try RoostBridge.shutdownHostd(mode: .release)
            } catch {
                NSLog("[Roost] release shutdown errored (ignored): %@",
                      String(describing: error))
            }
            return .terminateNow
        }

        // Stop path: ack is immediate but the actual reaping takes up to 6s
        // (SIGTERM 5s grace + SIGKILL 1s). Tell AppKit we'll reply later
        // and run the wait on a background queue.
        do {
            let live = try RoostBridge.shutdownHostd(mode: .stop)
            NSLog("[Roost] stop ack live=%u", live)
        } catch {
            NSLog("[Roost] stop ack errored, terminating now: %@",
                  String(describing: error))
            return .terminateNow
        }

        let timeout = terminateReplyTimeoutMs
        DispatchQueue.global(qos: .userInitiated).async {
            let dead = RoostBridge.waitHostdDead(timeoutMs: timeout)
            NSLog("[Roost] hostd reaped=%d (within %llu ms)", dead ? 1 : 0, timeout)
            DispatchQueue.main.async {
                NSApp.reply(toApplicationShouldTerminate: dead)
            }
        }
        return .terminateLater
    }
}
