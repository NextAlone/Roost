import AppKit
import Foundation
import SwiftUI

enum HostdOwnedTerminalInputEncoder {
    static func data(for event: NSEvent) -> Data? {
        data(
            characters: event.characters,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
    }

    static func data(
        characters: String?,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> Data? {
        guard !modifierFlags.contains(.command) else { return nil }
        if let mapped = mappedData(for: keyCode) { return mapped }
        guard let characters, !characters.isEmpty else { return nil }
        return characters.data(using: .utf8)
    }

    private static func mappedData(for keyCode: UInt16) -> Data? {
        switch keyCode {
        case 36,
             76:
            Data([13])
        case 48:
            Data([9])
        case 51:
            Data([127])
        case 53:
            Data([27])
        case 115:
            Data("\u{1B}[H".utf8)
        case 116:
            Data("\u{1B}[5~".utf8)
        case 117:
            Data("\u{1B}[3~".utf8)
        case 119:
            Data("\u{1B}[F".utf8)
        case 121:
            Data("\u{1B}[6~".utf8)
        case 123:
            Data("\u{1B}[D".utf8)
        case 124:
            Data("\u{1B}[C".utf8)
        case 125:
            Data("\u{1B}[B".utf8)
        case 126:
            Data("\u{1B}[A".utf8)
        default:
            nil
        }
    }
}

struct HostdOwnedTerminalInputBridge: NSViewRepresentable {
    let focused: Bool
    let visible: Bool
    let onFocus: () -> Void
    let onInput: (Data) -> Void

    func makeNSView(context: Context) -> HostdOwnedTerminalInputNSView {
        let view = HostdOwnedTerminalInputNSView()
        view.focused = focused
        view.visible = visible
        view.onFocus = onFocus
        view.onInput = onInput
        return view
    }

    func updateNSView(_ nsView: HostdOwnedTerminalInputNSView, context: Context) {
        nsView.focused = focused
        nsView.visible = visible
        nsView.onFocus = onFocus
        nsView.onInput = onInput
        nsView.updateFocus()
    }
}

final class HostdOwnedTerminalInputNSView: NSView {
    var focused = false
    var visible = false
    var onFocus: (() -> Void)?
    var onInput: ((Data) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func isAccessibilityElement() -> Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateFocus()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseDown
        else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        onFocus?()
    }

    override func keyDown(with event: NSEvent) {
        guard let data = HostdOwnedTerminalInputEncoder.data(for: event) else {
            super.keyDown(with: event)
            return
        }
        onInput?(data)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              isPasteShortcut(event)
        else { return false }
        paste(nil)
        return true
    }

    @objc
    func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string),
              let data = text.data(using: .utf8)
        else { return }
        onInput?(data)
    }

    func updateFocus() {
        guard focused, visible else { return }
        guard window?.firstResponder !== self else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.focused, self.visible else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    private func isPasteShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v"
    }
}
