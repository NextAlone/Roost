import SwiftUI

/// SwiftUI wrapper around `TerminalNSView`. One instance per session; caller
/// passes the session's `UUID` so ghostty's close callback can identify the
/// tab that just ended, plus `isFocused` so we can drive AppKit's
/// first-responder chain when the user switches tabs.
struct TerminalView: NSViewRepresentable {
    let sessionID: UUID
    let command: String?
    let workingDirectory: String?
    let isFocused: Bool

    init(
        sessionID: UUID,
        command: String? = nil,
        workingDirectory: String? = nil,
        isFocused: Bool
    ) {
        self.sessionID = sessionID
        self.command = command
        self.workingDirectory = workingDirectory
        self.isFocused = isFocused
    }

    func makeNSView(context: Context) -> TerminalNSView {
        TerminalNSView(
            sessionID: sessionID,
            command: command,
            workingDirectory: workingDirectory
        )
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {
        guard isFocused else { return }
        // Defer so SwiftUI finishes its own layout / focus pass first, then
        // re-check that the view is still in a window — SwiftUI can reparent
        // a view between the sync update and the async dispatch, which made
        // AppKit log "view is in a different window ((null))" and nil out
        // first responder.
        DispatchQueue.main.async {
            guard let currentWindow = nsView.window else { return }
            if currentWindow.firstResponder !== nsView {
                currentWindow.makeFirstResponder(nsView)
            }
        }
    }
}
