import AppKit
import SwiftUI

struct InactiveWindowClickView: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> InactiveWindowClickNSView {
        let view = InactiveWindowClickNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: InactiveWindowClickNSView, context: Context) {
        nsView.action = action
    }
}

final class InactiveWindowClickNSView: NSView {
    var action: (() -> Void)?

    override func isAccessibilityElement() -> Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard shouldCaptureCurrentMouseDown else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
        action?()
    }

    private var shouldCaptureCurrentMouseDown: Bool {
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseDown
        else { return false }
        guard let window else { return false }
        return !NSApp.isActive || !window.isKeyWindow
    }
}
