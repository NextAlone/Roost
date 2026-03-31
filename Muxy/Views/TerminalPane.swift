import SwiftUI
import AppKit

struct TerminalPane: View {
    let state: TerminalPaneState
    let focused: Bool
    let onFocus: () -> Void

    var body: some View {
        TerminalBridge(state: state, onFocus: onFocus)
    }
}

struct TerminalBridge: NSViewRepresentable {
    let state: TerminalPaneState
    let onFocus: () -> Void

    func makeNSView(context: Context) -> GhosttyTerminalNSView {
        let view = GhosttyTerminalNSView(workingDirectory: state.projectPath)
        view.onFocus = onFocus
        view.onTitleChange = { [weak state] title in
            state?.title = title
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: GhosttyTerminalNSView, context: Context) {}
}
