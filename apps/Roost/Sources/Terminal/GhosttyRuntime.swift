import Foundation
import GhosttyKit

extension Notification.Name {
    /// Posted when ghostty requests a surface close. `userInfo["sessionID"]`
    /// is the `UUID` of the owning `LaunchedSession` (or nil if we couldn't
    /// identify it).
    static let roostSurfaceClosed = Notification.Name("sh.roost.app.surfaceClosed")

    /// Posted when the child of a surface emits a desktop notification (OSC
    /// 9 / 99 / 777). `userInfo["sessionID"]` identifies the session;
    /// `"title"` and `"body"` carry the payload.
    static let roostAgentNotification = Notification.Name("sh.roost.app.agentNotification")

    /// Posted when the user hits ⌘W in a terminal; RootView closes the
    /// active tab.
    static let roostCloseActiveTab = Notification.Name("sh.roost.app.closeActiveTab")

    /// Posted when the user hits ⌘1-9; `userInfo["index"]` is zero-based.
    static let roostSelectTabByIndex = Notification.Name("sh.roost.app.selectTabByIndex")

    /// Posted when the user hits ⌘[ / ⌘]; `userInfo["delta"]` is -1 / +1.
    static let roostSelectRelativeTab = Notification.Name("sh.roost.app.selectRelativeTab")
}

/// Bundles the keys we use on `.roost*` `userInfo` dicts.
enum RoostNotificationKey {
    static let sessionID = "sessionID"
    static let title = "title"
    static let body = "body"
    static let index = "index"
    static let delta = "delta"
}

/// Singleton wrapper around `ghostty_app_t`. One per process; all surfaces
/// share this app handle. Created lazily on first access.
final class GhosttyRuntime {
    static let shared = GhosttyRuntime()

    let app: ghostty_app_t
    private let config: ghostty_config_t

    private init() {
        // ghostty_init runs global C++ constructors and must be called once
        // before any other ghostty_* API. Without it, ghostty_config_new
        // segfaults with EXC_BAD_ACCESS.
        if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != 0 {
            fatalError("ghostty_init failed")
        }

        config = ghostty_config_new()
        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)

        var runtime = ghostty_runtime_config_s(
            userdata: nil,
            supports_selection_clipboard: false,
            wakeup_cb: { _ in
                DispatchQueue.main.async {
                    ghostty_app_tick(GhosttyRuntime.shared.app)
                }
            },
            action_cb: { _, target, action in
                GhosttyRuntime.handleAction(target: target, action: action)
                // Accept everything silently for now — real routing (title
                // changes, tab ops, etc.) comes with later milestones.
                return true
            },
            read_clipboard_cb: { _, _, _ in false },
            confirm_read_clipboard_cb: { _, _, _, _ in },
            write_clipboard_cb: { _, _, _, _, _ in },
            close_surface_cb: { userdata, _ in
                // ghostty's runtime close callback passes the surface's
                // `userdata` (the value we set on `surface_config.userdata`).
                // We stored the `TerminalNSView` pointer there, so we can
                // recover the session ID it carries.
                let sessionID: UUID?
                if let userdata {
                    let view = Unmanaged<TerminalNSView>
                        .fromOpaque(userdata)
                        .takeUnretainedValue()
                    sessionID = view.sessionID
                } else {
                    sessionID = nil
                }
                DispatchQueue.main.async {
                    var info: [AnyHashable: Any] = [:]
                    if let sessionID {
                        info[RoostNotificationKey.sessionID] = sessionID
                    }
                    NotificationCenter.default.post(
                        name: .roostSurfaceClosed,
                        object: nil,
                        userInfo: info
                    )
                }
            }
        )

        guard let handle = ghostty_app_new(&runtime, config) else {
            fatalError("ghostty_app_new returned nil")
        }
        app = handle
    }

    /// Route interesting `action_cb` events back to SwiftUI via
    /// `NotificationCenter`. Keep this side-effect-free w.r.t. ghostty.
    fileprivate static func handleAction(
        target: ghostty_target_s,
        action: ghostty_action_s
    ) {
        NSLog("[Roost] action_cb tag=%u", action.tag.rawValue)
        switch action.tag {
        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            let notif = action.action.desktop_notification
            let title = notif.title.map { String(cString: $0) } ?? ""
            let body = notif.body.map { String(cString: $0) } ?? ""
            let sessionID = sessionID(from: target)
            NSLog("[Roost] desktop_notification session=%@ title=%@ body=%@",
                  sessionID?.uuidString ?? "nil", title, body)
            DispatchQueue.main.async {
                var info: [AnyHashable: Any] = [
                    RoostNotificationKey.title: title,
                    RoostNotificationKey.body: body,
                ]
                if let sessionID {
                    info[RoostNotificationKey.sessionID] = sessionID
                }
                NotificationCenter.default.post(
                    name: .roostAgentNotification,
                    object: nil,
                    userInfo: info
                )
            }
        default:
            break
        }
    }

    /// Translate a `ghostty_target_s` into the session UUID that lives on its
    /// `TerminalNSView`. Returns nil for app-level targets.
    private static func sessionID(from target: ghostty_target_s) -> UUID? {
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let surface = target.target.surface,
              let userdata = ghostty_surface_userdata(surface)
        else { return nil }
        let view = Unmanaged<TerminalNSView>
            .fromOpaque(userdata)
            .takeUnretainedValue()
        return view.sessionID
    }
}
