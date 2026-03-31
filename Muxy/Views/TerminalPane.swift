import SwiftUI
import AppKit

struct TerminalPane: View {
    let state: TerminalPaneState
    let focused: Bool
    let onFocus: () -> Void

    var body: some View {
        TerminalBridge(state: state, focused: focused, onFocus: onFocus)
    }
}

struct TerminalBridge: NSViewRepresentable {
    let state: TerminalPaneState
    let focused: Bool
    let onFocus: () -> Void

    final class Coordinator {
        var wasFocused = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> GhosttyTerminalNSView {
        let view = GhosttyTerminalNSView(workingDirectory: state.projectPath)
        view.onFocus = onFocus
        view.onTitleChange = { [weak state] title in
            state?.title = title
        }
        context.coordinator.wasFocused = focused
        if focused {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                view.window?.makeFirstResponder(view)
            }
        }
        return view
    }

    func updateNSView(_ nsView: GhosttyTerminalNSView, context: Context) {
        nsView.onFocus = onFocus
        let wasFocused = context.coordinator.wasFocused
        context.coordinator.wasFocused = focused
        guard focused, !wasFocused else { return }
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}
