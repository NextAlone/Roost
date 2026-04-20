import AppKit
import SwiftUI
import GhosttyKit

// MARK: - Runtime (one per process)

/// Singleton wrapper that creates `ghostty_app_t` once and survives for the
/// lifetime of the POC process. All surfaces share this app handle.
final class GhosttyRuntime {
    static let shared = GhosttyRuntime()

    let app: ghostty_app_t
    private let config: ghostty_config_t

    private init() {
        // ghostty_init runs global C++ constructors and must be called once
        // before any other ghostty_* API. Pass the process's real argv so that
        // `ghostty_cli_try_action` and diagnostics see it.
        let args = CommandLine.unsafeArgv
        let argc = CommandLine.argc
        if ghostty_init(UInt(argc), args) != 0 {
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
                // Stub: accept all actions (title change, tab ops, etc.) silently.
                return true
            },
            read_clipboard_cb: { _, _, _ in false },
            confirm_read_clipboard_cb: { _, _, _, _ in },
            write_clipboard_cb: { _, _, _, _, _ in },
            close_surface_cb: { _, _ in }
        )

        guard let handle = ghostty_app_new(&runtime, config) else {
            fatalError("ghostty_app_new returned nil")
        }
        app = handle
    }
}

// MARK: - NSView that hosts a ghostty surface

final class TerminalNSView: NSView {
    private var surface: ghostty_surface_t?
    private var markedText = NSMutableAttributedString()

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    // Create the ghostty surface once a window (and thus backingScaleFactor) exists.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard surface == nil, let window else { return }

        let nsviewPtr = Unmanaged.passUnretained(self).toOpaque()
        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: nsviewPtr)
        )
        cfg.userdata = nsviewPtr
        cfg.scale_factor = Double(window.backingScaleFactor)
        cfg.font_size = 0     // use config default
        cfg.working_directory = nil
        cfg.command = nil     // let ghostty pick the user's login shell
        cfg.env_vars = nil
        cfg.env_var_count = 0
        cfg.initial_input = nil
        cfg.wait_after_command = false
        cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        surface = ghostty_surface_new(GhosttyRuntime.shared.app, &cfg)
        if surface == nil {
            NSLog("ghostty_surface_new returned nil")
            return
        }

        // Push an initial size so ghostty knows our pixel dimensions.
        updateSurfaceSize()
        window.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        updateSurfaceSize()
    }

    private func updateSurfaceSize() {
        guard let surface, let window else { return }
        let scale = window.backingScaleFactor
        let w = UInt32(max(bounds.width * scale, 1))
        let h = UInt32(max(bounds.height * scale, 1))
        ghostty_surface_set_size(surface, w, h)
    }

    // MARK: Keyboard

    // Minimal key mapping: special keys (Enter/Backspace/Tab/Esc/Arrows) go
    // through ghostty_surface_key; printable text still goes through
    // ghostty_surface_text. Not a complete encoding — modifier shortcuts, IME,
    // and repeat handling are omitted.
    override func keyDown(with event: NSEvent) {
        guard let surface else { return }

        if let special = specialKey(for: event.keyCode) {
            var key = ghostty_input_key_s(
                action: GHOSTTY_ACTION_PRESS,
                mods: GHOSTTY_MODS_NONE,
                consumed_mods: GHOSTTY_MODS_NONE,
                keycode: UInt32(special.rawValue),
                text: nil,
                unshifted_codepoint: 0,
                composing: false
            )
            _ = ghostty_surface_key(surface, key)
            return
        }

        if let characters = event.characters, !characters.isEmpty {
            characters.withCString { cstr in
                ghostty_surface_text(surface, cstr, UInt(strlen(cstr)))
            }
        }
    }

    private func specialKey(for keyCode: UInt16) -> ghostty_input_key_e? {
        switch keyCode {
        case 0x24: return GHOSTTY_KEY_ENTER     // Return
        case 0x4C: return GHOSTTY_KEY_ENTER     // Numpad Enter
        case 0x33: return GHOSTTY_KEY_BACKSPACE // Delete (backspace)
        case 0x30: return GHOSTTY_KEY_TAB
        case 0x35: return GHOSTTY_KEY_ESCAPE
        case 0x7B: return GHOSTTY_KEY_ARROW_LEFT
        case 0x7C: return GHOSTTY_KEY_ARROW_RIGHT
        case 0x7D: return GHOSTTY_KEY_ARROW_DOWN
        case 0x7E: return GHOSTTY_KEY_ARROW_UP
        default: return nil
        }
    }

    // Stub so AppKit doesn't beep on modifier-only presses.
    override func flagsChanged(with event: NSEvent) {}

    deinit {
        if let surface { ghostty_surface_free(surface) }
    }
}

// MARK: - SwiftUI bridge

struct TerminalView: NSViewRepresentable {
    func makeNSView(context: Context) -> TerminalNSView {
        TerminalNSView(frame: .zero)
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {}
}
