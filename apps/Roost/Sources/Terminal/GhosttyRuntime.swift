import Foundation
import GhosttyKit

extension Notification.Name {
    /// Posted when ghostty requests a surface close. `userInfo["sessionID"]`
    /// is the `UUID` of the owning `LaunchedSession` (or nil if we couldn't
    /// identify it).
    static let roostSurfaceClosed = Notification.Name("sh.roost.app.surfaceClosed")
}

/// Bundles the keys we use on the `.roostSurfaceClosed` `userInfo` dict.
enum RoostNotificationKey {
    static let sessionID = "sessionID"
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
            action_cb: { _, _, _ in
                // Stub: accept all actions (title change, tab ops, etc.).
                // Real routing lands with M1+.
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
}
