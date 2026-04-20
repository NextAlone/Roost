import AppKit
import SwiftUI
import GhosttyKit

extension Notification.Name {
    /// Posted when ghostty requests the active surface close (child exit +
    /// `wait_after_command=true` -> user dismisses).
    static let roostSurfaceClosed = Notification.Name("sh.roost.poc.surfaceClosed")
}

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
            close_surface_cb: { _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .roostSurfaceClosed, object: nil)
                }
            }
        )

        guard let handle = ghostty_app_new(&runtime, config) else {
            fatalError("ghostty_app_new returned nil")
        }
        app = handle
    }
}

// MARK: - NSView that hosts a ghostty surface

final class TerminalNSView: NSView {
    /// Shell command ghostty spawns. `nil` = user's login shell.
    /// ghostty parses this as a shell-style string (supports args).
    let command: String?
    let workingDirectory: String?

    private var surface: ghostty_surface_t?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    init(command: String?, workingDirectory: String? = nil, frame: NSRect = .zero) {
        self.command = command
        // GUI-launched apps inherit launchd's cwd ('/'), which makes ghostty
        // spawn shells in '/'. Default to $HOME when the caller doesn't care.
        self.workingDirectory = workingDirectory ?? NSHomeDirectory()
        super.init(frame: frame)
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
        cfg.font_size = 0
        cfg.env_vars = nil
        cfg.env_var_count = 0
        cfg.initial_input = nil
        // When running an explicit command (agent CLI) rather than a login
        // shell, keep the surface alive after exit so the user can read the
        // status and dismiss with Enter. ghostty then calls close_surface_cb.
        cfg.wait_after_command = (command != nil)
        cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        // ghostty_surface_new copies these strings internally, so pointer
        // lifetimes only need to outlive the call.
        withOptionalCString(command) { cmdPtr in
            withOptionalCString(workingDirectory) { wdPtr in
                cfg.command = cmdPtr
                cfg.working_directory = wdPtr
                surface = ghostty_surface_new(GhosttyRuntime.shared.app, &cfg)
            }
        }

        if surface == nil {
            NSLog("ghostty_surface_new returned nil (command=\(command ?? "nil"))")
            return
        }

        updateSurfaceSize()
        window.makeFirstResponder(self)
    }

    private func withOptionalCString<R>(
        _ s: String?,
        _ body: (UnsafePointer<CChar>?) -> R
    ) -> R {
        if let s { return s.withCString { body($0) } }
        return body(nil)
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

    override func keyDown(with event: NSEvent) {
        forward(event: event, action: GHOSTTY_ACTION_PRESS)
    }

    override func keyUp(with event: NSEvent) {
        forward(event: event, action: GHOSTTY_ACTION_RELEASE)
    }

    // Stub so AppKit doesn't beep on modifier-only presses.
    override func flagsChanged(with event: NSEvent) {}

    private func forward(event: NSEvent, action: ghostty_input_action_e) {
        guard let surface else { return }

        // ghostty's `keycode` field expects the macOS virtual keyCode directly
        // (see ghostty's Input.swift — it maps Key.enter → 0x24 etc., which is
        // the NSEvent.keyCode value).
        let mods = modsFrom(event.modifierFlags)

        let runKey: (UnsafePointer<CChar>?) -> Void = { textPtr in
            var k = ghostty_input_key_s(
                action: action,
                mods: mods,
                consumed_mods: GHOSTTY_MODS_NONE,
                keycode: UInt32(event.keyCode),
                text: textPtr,
                unshifted_codepoint: 0,
                composing: false
            )
            _ = ghostty_surface_key(surface, k)
        }

        let chars = event.characters ?? ""
        if !chars.isEmpty && !isFunctionKeyCharacters(chars) {
            chars.withCString { runKey($0) }
        } else {
            runKey(nil)
        }
    }

    /// AppKit puts arrow / function keys in `event.characters` as private-use
    /// codepoints (U+F700..U+F8FF = "NSUpArrowFunctionKey" etc.). ghostty
    /// treats a non-nil `text` as user-visible input and skips its own arrow
    /// handling, so we must strip these.
    private func isFunctionKeyCharacters(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { (0xF700...0xF8FF).contains($0.value) }
    }

    private func modsFrom(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw: UInt32 = 0
        if flags.contains(.shift)    { raw |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control)  { raw |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option)   { raw |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command)  { raw |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: raw)
    }

    deinit {
        if let surface { ghostty_surface_free(surface) }
    }
}

// MARK: - SwiftUI bridge

struct TerminalView: NSViewRepresentable {
    let command: String?
    let workingDirectory: String?

    init(command: String? = nil, workingDirectory: String? = nil) {
        self.command = command
        self.workingDirectory = workingDirectory
    }

    func makeNSView(context: Context) -> TerminalNSView {
        TerminalNSView(command: command, workingDirectory: workingDirectory)
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {}
}
