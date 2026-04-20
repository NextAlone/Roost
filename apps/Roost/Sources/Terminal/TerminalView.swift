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
        guard isFocused, let window = nsView.window else { return }
        // Defer until the run loop settles so SwiftUI's own layout pass
        // doesn't reclaim first responder after we set it.
        DispatchQueue.main.async {
            if window.firstResponder !== nsView {
                window.makeFirstResponder(nsView)
            }
        }
    }
}
