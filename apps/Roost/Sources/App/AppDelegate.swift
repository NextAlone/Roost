import AppKit
import SwiftUI

/// Adopt the running hostd (or spawn one) at launch, and route ⌘Q through a
/// notification-style shutdown so AppKit doesn't SIGKILL the process before
/// hostd's grace period finishes.
final class RoostAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    /// Latest hostd snapshot, polled lazily by views that want it (About,
    /// menu badge). Refreshed on-demand from `refreshHostdStatus()`.
    @Published private(set) var hostdStatus: HostdStatusSwift?
    @Published private(set) var hostdError: String?

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
