import SwiftUI

/// SwiftUI wrapper around `TerminalNSView`. Stateless re: session — for a new
/// session, rebuild by changing `.id(...)` on the parent.
struct TerminalView: NSViewRepresentable {
    let command: String?
    let workingDirectory: String?

    init(command: String? = nil, workingDirectory: String? = nil) {
        self.command = command
        self.workingDirectory = workingDirectory
    }

    func makeNSView(context: Context) -> TerminalNSView {
        TerminalNSView(command: command, workingDirectory: workingDirectory)
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {}
}
