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

    // Minimal: forward composed text. This is NOT a correct key encoding and
    // will miss modifier-bound shortcuts, arrow keys, etc. — enough to prove
    // the PTY round-trip on typing.
    override func keyDown(with event: NSEvent) {
        guard let surface else { return }
        if let characters = event.characters, !characters.isEmpty {
            characters.withCString { cstr in
                ghostty_surface_text(surface, cstr, UInt(strlen(cstr)))
            }
        }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard let surface, let text = string as? String else { return }
        text.withCString { cstr in
            ghostty_surface_text(surface, cstr, UInt(strlen(cstr)))
        }
    }

    // Stubs so AppKit doesn't beep on modifier-only presses and dead keys.
    override func flagsChanged(with event: NSEvent) {}
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    override func unmarkText() {}
    override func hasMarkedText() -> Bool { false }

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
