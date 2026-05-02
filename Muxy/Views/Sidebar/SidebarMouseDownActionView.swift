import AppKit
import SwiftUI

struct SidebarMouseDownActionView: NSViewRepresentable {
    let action: (Int) -> Void

    func makeNSView(context: Context) -> SidebarMouseDownActionNSView {
        let view = SidebarMouseDownActionNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: SidebarMouseDownActionNSView, context: Context) {
        nsView.action = action
    }
}

final class SidebarMouseDownActionNSView: NSView {
    nonisolated(unsafe) private var monitor: Any?
    var action: ((Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func handle(_ event: NSEvent) {
        guard let window, event.window === window else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        action?(event.clickCount)
    }
}
