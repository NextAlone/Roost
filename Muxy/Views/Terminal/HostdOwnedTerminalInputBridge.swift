import AppKit
import Foundation
import RoostHostdCore
import SwiftUI

enum HostdOwnedTerminalInputAction: Equatable {
    case input(Data)
    case signal(HostdSessionSignal)
}

enum HostdOwnedTerminalInputEncoder {
    static func action(for event: NSEvent) -> HostdOwnedTerminalInputAction? {
        action(
            characters: event.characters,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
    }

    static func action(
        characters: String?,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> HostdOwnedTerminalInputAction? {
        guard !modifierFlags.contains(.command) else { return nil }
        if isInterrupt(characters: characters, keyCode: keyCode, modifierFlags: modifierFlags) {
            return .signal(.interrupt)
        }
        if let mapped = mappedData(for: keyCode) { return .input(mapped) }
        guard let characters, !characters.isEmpty else { return nil }
        guard let data = characters.data(using: .utf8) else { return nil }
        return .input(data)
    }

    static func data(for event: NSEvent) -> Data? {
        data(action: action(
            characters: event.characters,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        ))
    }

    static func data(
        characters: String?,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> Data? {
        data(action: action(characters: characters, keyCode: keyCode, modifierFlags: modifierFlags))
    }

    private static func data(action: HostdOwnedTerminalInputAction?) -> Data? {
        guard case let .input(data) = action else { return nil }
        return data
    }

    private static func isInterrupt(
        characters: String?,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        characters == "\u{3}" || (modifierFlags.contains(.control) && keyCode == 8)
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
    let onAction: (HostdOwnedTerminalInputAction) -> Void

    func makeNSView(context: Context) -> HostdOwnedTerminalInputNSView {
        let view = HostdOwnedTerminalInputNSView()
        view.focused = focused
        view.visible = visible
        view.onFocus = onFocus
        view.onAction = onAction
        return view
    }

    func updateNSView(_ nsView: HostdOwnedTerminalInputNSView, context: Context) {
        nsView.focused = focused
        nsView.visible = visible
        nsView.onFocus = onFocus
        nsView.onAction = onAction
        nsView.updateFocus()
    }
}

final class HostdOwnedTerminalInputNSView: NSView {
    var focused = false
    var visible = false
    var onFocus: (() -> Void)?
    var onAction: ((HostdOwnedTerminalInputAction) -> Void)?

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
        guard let action = HostdOwnedTerminalInputEncoder.action(for: event) else {
            super.keyDown(with: event)
            return
        }
        onAction?(action)
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
        onAction?(.input(data))
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
