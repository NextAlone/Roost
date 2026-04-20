import AppKit
import GhosttyKit

/// `NSView` that owns a single `ghostty_surface_t` and forwards keyboard /
/// layout events to it. libghostty mounts a `CAMetalLayer` on this view and
/// spawns the requested command (or the user's login shell) behind the scenes.
final class TerminalNSView: NSView {
    /// Owning session's identity. Used by `close_surface_cb` to tell the UI
    /// which tab to tear down.
    let sessionID: UUID
    /// Shell-style command string ghostty will spawn. `nil` = login shell.
    let command: String?
    let workingDirectory: String?

    private var surface: ghostty_surface_t?

    // MARK: IME (NSTextInputClient) state

    /// Preedit / marked text currently being composed by a macOS input
    /// method (Pinyin, Hangul, Kotoeri, dead-keys, emoji picker).
    private let markedText = NSMutableAttributedString()
    /// When non-nil we're inside `keyDown`; `insertText(_:replacementRange:)`
    /// appends to this instead of sending to ghostty immediately so the
    /// keystroke that confirmed the IME doesn't double-encode.
    private var keyTextAccumulator: [String]?
    /// Set by `doCommand(by:)` when it forwarded the current event to
    /// ghostty. Outer `keyDown` checks this to avoid double-dispatching
    /// arrow keys / Ctrl+letter.
    private var consumedViaDoCommand = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    init(
        sessionID: UUID,
        command: String?,
        workingDirectory: String? = nil,
        frame: NSRect = .zero
    ) {
        self.sessionID = sessionID
        self.command = command
        // GUI-launched apps inherit launchd's cwd ('/'), which makes ghostty
        // spawn shells in '/'. Default to $HOME when the caller doesn't care.
        self.workingDirectory = workingDirectory ?? NSHomeDirectory()
        super.init(frame: frame)
        wantsLayer = true
        NSLog("[Roost] TerminalNSView init session=%@", sessionID.uuidString)

        // When the user switches IME while a preedit is active (⌃Space,
        // etc.), AppKit doesn't always notify the old IME to discard its
        // marked text, leaving stale glyphs on ghostty's cursor. Hook the
        // system notification and flush.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(inputSourceDidChange(_:)),
            name: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Lifecycle

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
        cfg.initial_input = nil
        // Running an explicit command (agent CLI) rather than a login shell:
        // keep the surface alive after exit so the user can read exit status
        // and dismiss with Enter; ghostty then calls close_surface_cb.
        cfg.wait_after_command = (command != nil)
        cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        // Build env_vars. ghostty copies these internally on
        // ghostty_surface_new, so the strdup'd buffers can be freed after
        // the call returns.
        let envPairs = Self.defaultEnvPairs()
        var cEnv: [ghostty_env_var_s] = envPairs.map { pair in
            ghostty_env_var_s(
                key: strdup(pair.0),
                value: strdup(pair.1)
            )
        }
        defer {
            for var e in cEnv {
                free(UnsafeMutableRawPointer(mutating: e.key))
                free(UnsafeMutableRawPointer(mutating: e.value))
                _ = e
            }
        }

        cEnv.withUnsafeMutableBufferPointer { envBuf in
            cfg.env_vars = envBuf.baseAddress
            cfg.env_var_count = envBuf.count
            withOptionalCString(command) { cmdPtr in
                withOptionalCString(workingDirectory) { wdPtr in
                    cfg.command = cmdPtr
                    cfg.working_directory = wdPtr
                    surface = ghostty_surface_new(GhosttyRuntime.shared.app, &cfg)
                }
            }
        }

        if surface == nil {
            NSLog("ghostty_surface_new returned nil (command=\(command ?? "nil"))")
            return
        }

        updateSurfaceSize()
        window.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        updateSurfaceSize()
    }

    deinit {
        NSLog("[Roost] TerminalNSView deinit session=%@ surface=%@",
              sessionID.uuidString,
              surface == nil ? "nil" : "set")
        NotificationCenter.default.removeObserver(self)
        if let surface { ghostty_surface_free(surface) }
    }

    /// Called when the active macOS input source changes. If we had a
    /// live preedit under the *old* IME, flush it: tell the old IME to
    /// discard its marked text, clear our mirror, and clear ghostty's
    /// preedit so no glyphs linger in the cursor cell.
    @objc private func inputSourceDidChange(_ note: Notification) {
        guard markedText.length > 0 else { return }
        markedText.mutableString.setString("")
        inputContext?.discardMarkedText()
        syncPreedit(clearIfNeeded: true)
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
        // Intercept standard macOS shortcuts before they leak into the PTY.
        // Ghostty has a configurable keybind system; for MVP we hardcode the
        // common subset here so agents running in a surface don't swallow
        // these host-level actions.
        if event.modifierFlags.contains(.command),
           event.modifierFlags.intersection([.control, .option]).isEmpty,
           handleCommandShortcut(event) {
            return
        }

        // Route through the IME pipeline first so CJK / Hangul / dead-key
        // composition can translate keystrokes into `insertText` /
        // `setMarkedText` callbacks below. On pass-through the IME calls
        // `doCommand(by:)`, which forwards the raw event to ghostty.
        let hadMarkedText = hasMarkedText()
        keyTextAccumulator = []
        consumedViaDoCommand = false
        defer {
            keyTextAccumulator = nil
            consumedViaDoCommand = false
        }

        _ = inputContext?.handleEvent(event)

        // Sync preedit state: if IME set marked text, push to ghostty as
        // preedit; if it cleared, clear ghostty's preedit too.
        syncPreedit(clearIfNeeded: hadMarkedText)

        // IME confirmed one or more strings via insertText; commit them as a
        // single text batch (`ghostty_surface_text`). Path for
        // "type Pinyin + space → 汉字", emoji picker, etc.
        if let strings = keyTextAccumulator, !strings.isEmpty {
            let joined = strings.joined()
            if !joined.isEmpty, let surface {
                joined.withCString { cstr in
                    ghostty_surface_text(surface, cstr, UInt(strlen(cstr)))
                }
            }
            return
        }

        // IME routed the event to `doCommand(by:)` (arrow keys, Ctrl+letter,
        // Enter while not composing). That path already forwarded the event
        // to ghostty — don't double-send.
        if consumedViaDoCommand {
            return
        }

        // Still composing (marked text unchanged or just entered). Preedit
        // owns the glyph; don't emit an extra keystroke to ghostty.
        if hasMarkedText() || hadMarkedText {
            return
        }

        // Fallback: IME ignored the event entirely. Send it raw.
        forward(event: event, action: GHOSTTY_ACTION_PRESS)
    }

    /// Returns true if the event was consumed (and so must not reach ghostty).
    private func handleCommandShortcut(_ event: NSEvent) -> Bool {
        let chars = event.charactersIgnoringModifiers ?? ""
        switch chars {
        case "v":
            return pasteFromClipboard()
        case "c":
            return copySelectionToClipboard()
        case "w":
            postTabNotification(.roostCloseActiveTab)
            return true
        case "[":
            postTabNotification(.roostSelectRelativeTab, userInfo: [RoostNotificationKey.delta: -1])
            return true
        case "]":
            postTabNotification(.roostSelectRelativeTab, userInfo: [RoostNotificationKey.delta: 1])
            return true
        case "=", "+":
            return triggerBindingAction("increase_font_size:1")
        case "-":
            return triggerBindingAction("decrease_font_size:1")
        case "0":
            return triggerBindingAction("reset_font_size")
        default:
            if chars.count == 1, let digit = chars.first, digit.isNumber {
                if let idx = digit.hexDigitValue, idx >= 1, idx <= 9 {
                    postTabNotification(
                        .roostSelectTabByIndex,
                        userInfo: [RoostNotificationKey.index: idx - 1]
                    )
                    return true
                }
            }
            return false
        }
    }

    private func postTabNotification(
        _ name: Notification.Name,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        NotificationCenter.default.post(name: name, object: sessionID, userInfo: userInfo)
    }

    @discardableResult
    private func triggerBindingAction(_ name: String) -> Bool {
        guard let surface else { return false }
        return name.withCString { cstr in
            ghostty_surface_binding_action(surface, cstr, UInt(strlen(cstr)))
        }
    }

    @discardableResult
    private func pasteFromClipboard() -> Bool {
        guard let surface,
              let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty
        else { return false }
        text.withCString { cstr in
            ghostty_surface_text(surface, cstr, UInt(strlen(cstr)))
        }
        return true
    }

    @discardableResult
    private func copySelectionToClipboard() -> Bool {
        guard let surface, ghostty_surface_has_selection(surface) else {
            return false
        }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return false }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let ptr = text.text, text.text_len > 0 else { return false }
        let data = Data(bytes: ptr, count: Int(text.text_len))
        guard let str = String(data: data, encoding: .utf8) else { return false }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(str, forType: .string)
        return true
    }

    override func keyUp(with event: NSEvent) {
        forward(event: event, action: GHOSTTY_ACTION_RELEASE)
    }

    /// Stub so AppKit doesn't beep on modifier-only presses.
    override func flagsChanged(with event: NSEvent) {}

    private func forward(event: NSEvent, action: ghostty_input_action_e) {
        guard let surface else { return }

        // ghostty's `keycode` field expects the macOS virtual keyCode (Key.enter
        // → 0x24 etc.), not the `GHOSTTY_KEY_*` ordinal.
        let mods = modsFrom(event.modifierFlags)

        // unshifted_codepoint = what character this key would produce with NO
        // modifiers. ghostty's KeyEncoder uses it to pick the correct control
        // byte for Ctrl+<letter>. Missing it → Ctrl+C leaks as literal 'c'.
        let unshifted: UInt32 = {
            guard event.type == .keyDown || event.type == .keyUp,
                  let chars = event.characters(byApplyingModifiers: []),
                  let scalar = chars.unicodeScalars.first
            else { return 0 }
            return scalar.value
        }()

        // consumed_mods heuristic (upstream): .control and .command never
        // contribute to text translation.
        let consumed = modsFrom(event.modifierFlags.subtracting([.control, .command]))

        let runKey: (UnsafePointer<CChar>?) -> Void = { textPtr in
            let k = ghostty_input_key_s(
                action: action,
                mods: mods,
                consumed_mods: consumed,
                keycode: UInt32(event.keyCode),
                
                /// Mirror of ghostty's upstream `NSEvent.ghosttyCharacters`: strip control
                /// bytes (< 0x20) and function-key PUA codepoints (U+F700..U+F8FF) from
                text: textPtr,
                unshifted_codepoint: unshifted,
                composing: false
            )
            _ = ghostty_surface_key(surface, k)
        }

        if let text = ghosttyCharacters(from: event),
           !text.isEmpty,
           let first = text.utf8.first,
           first >= 0x20 {
            text.withCString { runKey($0) }
        } else {
            runKey(nil)
        }
    }
    /// `event.characters`. For Ctrl+<letter> we return the plain letter so
    /// ghostty's KeyEncoder can emit the correct control byte itself; passing
    /// \u{03} as `text` makes ghostty double-encode and breaks Ctrl+C.
    private func ghosttyCharacters(from event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return event.characters(
                    byApplyingModifiers: event.modifierFlags.subtracting(.control)
                )
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }
        return characters
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

    // MARK: IME bridge

    private func syncPreedit(clearIfNeeded: Bool) {
        guard let surface else { return }
        if markedText.length > 0 {
            let s = markedText.string
            s.withCString { cstr in
                ghostty_surface_preedit(surface, cstr, UInt(strlen(cstr)))
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    private func withOptionalCString<R>(
        _ s: String?,
        _ body: (UnsafePointer<CChar>?) -> R
    ) -> R {
        if let s { return s.withCString { body($0) } }
        return body(nil)
    }

    /// Env vars injected into every session so agents inherit sensible
    /// defaults. Currently ships the bundled xterm-ghostty terminfo so
    /// less / nano / tmux stop complaining about "terminal is not fully
    /// functional".
    private static func defaultEnvPairs() -> [(String, String)] {
        var out: [(String, String)] = []
        if let resPath = Bundle.main.resourcePath {
            let terminfo = (resPath as NSString).appendingPathComponent("terminfo")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: terminfo, isDirectory: &isDir),
               isDir.boolValue {
                out.append(("TERMINFO", terminfo))
            }
        }
        return out
    }
}

// MARK: - NSTextInputClient (IME / dead-keys / emoji picker)

extension TerminalNSView: NSTextInputClient {
    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedText.length)
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        switch string {
        case let v as NSAttributedString:
            markedText.setAttributedString(v)
        case let v as String:
            markedText.mutableString.setString(v)
        default:
            markedText.mutableString.setString("")
        }
        // Mid-keyDown the outer loop will call `syncPreedit`. For external
        // events (e.g. keyboard layout change while composing) push now.
        if keyTextAccumulator == nil {
            syncPreedit(clearIfNeeded: true)
        }
    }

    func unmarkText() {
        guard markedText.length > 0 else { return }
        markedText.mutableString.setString("")
        if keyTextAccumulator == nil {
            syncPreedit(clearIfNeeded: true)
        }
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? { nil }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String = {
            if let s = string as? String { return s }
            if let a = string as? NSAttributedString { return a.string }
            return ""
        }()
        guard !text.isEmpty else { return }

        // Confirmation → clear preedit locally; syncPreedit in outer keyDown
        // will push the clear to ghostty.
        if markedText.length > 0 {
            markedText.mutableString.setString("")
        }

        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
        } else if let surface {
            // Called from outside a keyDown (emoji picker etc.): commit now.
            text.withCString { cstr in
                ghostty_surface_text(surface, cstr, UInt(strlen(cstr)))
            }
        }
    }

    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    func firstRect(
        forCharacterRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSRect {
        // Ask ghostty where the cursor cell is. It answers in top-left view
        // pixels; AppKit wants bottom-left, so we flip on the view's height.
        guard let surface, let window else { return .zero }
        var x: Double = 0
        var y: Double = 0
        var width: Double = 0
        var height: Double = 0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)

        let viewRect = NSRect(
            x: x,
            y: Double(frame.size.height) - y,
            width: width,
            height: height
        )
        let winRect = convert(viewRect, to: nil)
        return window.convertToScreen(winRect)
    }

    // `doCommand(by:)` is declared on NSResponder too, so this must be an
    // override rather than a fresh protocol method.
    override func doCommand(by selector: Selector) {
        // IME passed the event back to AppKit without consuming it (arrow
        // keys, esc, return while not composing). Forward the original event
        // to ghostty as a raw keystroke so its KeyEncoder can emit the
        // correct escape sequence. Flag it so outer keyDown skips its
        // fallback path and we don't double-send.
        if let event = NSApp.currentEvent, event.type == .keyDown {
            forward(event: event, action: GHOSTTY_ACTION_PRESS)
            consumedViaDoCommand = true
        }
    }
}
