import Foundation
import GhosttyKit

extension Notification.Name {
    /// Posted when ghostty requests the active surface close (child exit +
    /// `wait_after_command=true` → user dismisses).
    static let roostSurfaceClosed = Notification.Name("sh.roost.app.surfaceClosed")
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
            close_surface_cb: { _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .roostSurfaceClosed, object: nil)
                }
            }
        )

        guard let handle = ghostty_app_new(&runtime, config) else {
            fatalError("ghostty_app_new returned nil")
        }
        app = handle
    }
}
