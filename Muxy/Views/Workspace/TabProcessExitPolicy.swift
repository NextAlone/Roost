enum TabProcessExitPolicy {
    @MainActor
    static func representsPaneSessionExit(_ pane: TerminalPaneState) -> Bool {
        pane.hostdRuntimeOwnership != .hostdOwnedProcess
    }

    @MainActor
    static func shouldForceCloseTabAfterPaneSessionExit(_ pane: TerminalPaneState) -> Bool {
        representsPaneSessionExit(pane) && pane.agentKind == .terminal
    }
}
