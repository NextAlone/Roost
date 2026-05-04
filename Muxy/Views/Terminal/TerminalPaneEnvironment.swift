import Foundation
import RoostHostdCore

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
        if vars["COLORTERM"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            vars["COLORTERM"] = "truecolor"
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

    static func hostdLaunchCommand(
        _ command: String?,
        environment: [String: String],
        exportTerm: Bool = true
    ) -> String? {
        guard let command else { return nil }
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return command }
        let keys = exportTerm ? ["PATH", "SHELL", "TERM"] : ["PATH", "SHELL"]
        let exports = keys.compactMap { key -> String? in
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
        tmuxPath: String = "tmux"
    ) -> String {
        let tmux = ShellEscaper.escape(tmuxPath)
        let session = ShellEscaper.escape(HostdTmuxSessionName.name(for: sessionID))
        return [
            "\(tmux) set-option -gq 'terminal-features[100]' xterm-256color:RGB:extkeys",
            "set-option -gq 'terminal-features[101]' xterm-ghostty:RGB:extkeys",
            "set-option -gq 'terminal-features[102]' \(ShellEscaper.escape("ghostty*:RGB:extkeys"))",
            "set-option -gq extended-keys always",
            "set-option -gq extended-keys-format csi-u",
            "set-option -t \(session) mouse on",
            "set-option -t \(session) status off",
            "set-option -t \(session) prefix None",
            "set-option -t \(session) prefix2 None",
            "bind-key -T root WheelUpPane \(ShellEscaper.escape(rootWheelUpBinding))",
            "bind-key -T copy-mode Enter \(ShellEscaper.escape(copyModeEnterBinding))",
            "bind-key -T copy-mode-vi Enter \(ShellEscaper.escape(copyModeEnterBinding))",
            "bind-key -T copy-mode WheelUpPane send-keys -X -N 1 scroll-up",
            "bind-key -T copy-mode WheelDownPane send-keys -X -N 1 scroll-down",
            "bind-key -T copy-mode-vi WheelUpPane send-keys -X -N 1 scroll-up",
            "bind-key -T copy-mode-vi WheelDownPane send-keys -X -N 1 scroll-down",
            "attach-session -t \(session)",
        ].joined(separator: " \\; ")
    }

    private static let rootWheelUpBinding =
        ##"if-shell -F "#{||:#{alternate_on},#{pane_in_mode},#{mouse_any_flag}}" "##
            + ##""send-keys -M" "copy-mode -e; send-keys -X -N 1 scroll-up""##

    private static let copyModeEnterBinding =
        ##"if-shell -F "#{selection_present}" "send-keys -X copy-pipe-and-cancel" "##
            + ##""send-keys -X cancel; send-keys Enter""##
}
