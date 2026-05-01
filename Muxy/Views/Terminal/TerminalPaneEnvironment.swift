import Foundation

enum TerminalPaneEnvironment {
    static func build(
        paneID: UUID,
        worktreeKey key: WorktreeKey,
        configured: [String: String],
        shellPath: String = UserShellEnvironmentResolver.path(),
        shell: String = UserShellResolver.shell()
    ) -> [String: String] {
        var vars = configured
        if vars["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            vars["PATH"] = shellPath
        }
        if vars["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            vars["SHELL"] = shell
        }
        vars["MUXY_PANE_ID"] = paneID.uuidString
        vars["MUXY_PROJECT_ID"] = key.projectID.uuidString
        vars["MUXY_WORKTREE_ID"] = key.worktreeID.uuidString
        vars["MUXY_SOCKET_PATH"] = NotificationSocketServer.socketPath
        if let hookPath = MuxyNotificationHooks.hookScriptPath {
            vars["MUXY_HOOK_SCRIPT"] = hookPath
        }
        return vars
    }

    static func ordered(
        paneID: UUID,
        worktreeKey key: WorktreeKey,
        configured: [String: String]
    ) -> [(key: String, value: String)] {
        build(paneID: paneID, worktreeKey: key, configured: configured)
            .map { (key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key }
    }
}
