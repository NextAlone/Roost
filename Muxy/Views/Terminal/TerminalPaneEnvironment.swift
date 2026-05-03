import Foundation

enum TerminalPaneEnvironment {
    static func build(
        paneID: UUID,
        worktreeKey key: WorktreeKey,
        configured: [String: String],
        shellPath: @autoclosure () -> String = UserShellEnvironmentResolver.cachedPath(),
        shell: @autoclosure () -> String = UserShellResolver.shell()
    ) -> [String: String] {
        var vars = configured
        if vars["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            vars["PATH"] = shellPath()
        }
        if vars["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            vars["SHELL"] = shell()
        }
        if vars["TERM"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            vars["TERM"] = "xterm-256color"
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

    static func hostdLaunchCommand(_ command: String?, environment: [String: String]) -> String? {
        guard let command else { return nil }
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return command }
        let exports = ["PATH", "SHELL", "TERM"].compactMap { key -> String? in
            guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { return nil }
            return "export \(key)=\(ShellEscaper.escape(value))"
        }
        guard !exports.isEmpty else { return trimmedCommand }
        return "\(exports.joined(separator: "; ")); \(trimmedCommand)"
    }

    static func hostdAttachCommand(
        sessionID: UUID,
        helperPath: String? = HostdAttachHelperLocator.helperPath(),
        socketPath: String = HostdDaemonLauncher.defaultSocketPath
    ) -> String {
        guard let helperPath,
              !helperPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return "printf %s\\\\n 'roost-hostd-attach helper not found'; exit 127"
        }
        let helper = ShellEscaper.escape(helperPath)
        let session = ShellEscaper.escape(sessionID.uuidString)
        let socket = ShellEscaper.escape(socketPath)
        return "\(helper) --session \(session) --socket \(socket)"
    }
}

enum HostdAttachHelperLocator {
    static func helperPath(
        bundleURL: URL = Bundle.main.bundleURL,
        executableURL: URL? = Bundle.main.executableURL,
        fileExists: (String) -> Bool = FileManager.default.fileExists
    ) -> String? {
        let bundled = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("roost-hostd-attach")
            .path(percentEncoded: false)
        if fileExists(bundled) { return bundled }

        guard let executableURL else { return nil }
        let adjacent = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("roost-hostd-attach")
            .path(percentEncoded: false)
        if fileExists(adjacent) { return adjacent }
        return nil
    }
}
