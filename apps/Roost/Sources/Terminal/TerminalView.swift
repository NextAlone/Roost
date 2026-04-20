import SwiftUI

/// SwiftUI wrapper around `TerminalNSView`. One instance per session; caller
/// passes the session's `UUID` so ghostty's close callback can identify the
/// tab that just ended.
struct TerminalView: NSViewRepresentable {
    let sessionID: UUID
    let command: String?
    let workingDirectory: String?

    init(sessionID: UUID, command: String? = nil, workingDirectory: String? = nil) {
        self.sessionID = sessionID
        self.command = command
        self.workingDirectory = workingDirectory
    }

    func makeNSView(context: Context) -> TerminalNSView {
        TerminalNSView(
            sessionID: sessionID,
            command: command,
            workingDirectory: workingDirectory
        )
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {}
}
