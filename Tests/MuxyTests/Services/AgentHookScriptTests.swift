import Foundation
import Testing

@Suite("Agent hook scripts")
struct AgentHookScriptTests {
    @Test("Claude hook emits activity-qualified socket types")
    func claudeHookTypes() throws {
        let script = try resourceText("Muxy/Resources/scripts/roost-claude-hook.sh")
        #expect(script.contains("\"claude_hook:idle\""))
        #expect(script.contains("\"claude_hook:running\""))
        #expect(script.contains("\"claude_hook:needs_input\""))
        #expect(script.contains("\"claude_hook:completed\""))
        #expect(script.contains("nc -w 1 -U"))
        #expect(script.contains("ROOST_SOCKET_PATH"))
        #expect(script.contains("ROOST_PANE_ID"))
    }

    @Test("Codex hook emits activity-qualified socket types")
    func codexHookTypes() throws {
        let script = try resourceText("Muxy/Resources/scripts/roost-codex-hook.sh")
        #expect(script.contains("\"codex_hook:idle\""))
        #expect(script.contains("\"codex_hook:running\""))
        #expect(script.contains("\"codex_hook:needs_input\""))
        #expect(script.contains("\"codex_hook:completed\""))
        #expect(script.contains("PermissionRequest"))
        #expect(script.contains("nc -w 1 -U"))
        #expect(script.contains("ROOST_SOCKET_PATH"))
        #expect(script.contains("ROOST_PANE_ID"))
    }

    @Test("Cursor hook emits activity-qualified socket types")
    func cursorHookTypes() throws {
        let script = try resourceText("Muxy/Resources/scripts/roost-cursor-hook.sh")
        #expect(script.contains("\"cursor_hook:needs_input\""))
        #expect(script.contains("\"cursor_hook:completed\""))
        #expect(script.contains("nc -w 1 -U"))
        #expect(script.contains("ROOST_SOCKET_PATH"))
        #expect(script.contains("ROOST_PANE_ID"))
    }

    @Test("OpenCode plugin emits idle activity")
    func openCodeIdleType() throws {
        let script = try resourceText("Muxy/Resources/scripts/opencode-roost-plugin.js")
        #expect(script.contains("opencode:idle"))
        #expect(script.contains("ROOST_SOCKET_PATH"))
        #expect(script.contains("ROOST_PANE_ID"))
    }

    @Test("legacy hook script names remain wrappers")
    func legacyHookNamesRemainWrappers() throws {
        #expect(try resourceText("Muxy/Resources/scripts/muxy-claude-hook.sh").contains("roost-claude-hook.sh"))
        #expect(try resourceText("Muxy/Resources/scripts/muxy-codex-hook.sh").contains("roost-codex-hook.sh"))
        #expect(try resourceText("Muxy/Resources/scripts/muxy-cursor-hook.sh").contains("roost-cursor-hook.sh"))
        #expect(try resourceText("Muxy/Resources/scripts/opencode-muxy-plugin.js").contains("opencode-roost-plugin.js"))
    }

    @Test("Claude wrapper uses Roost contract")
    func claudeWrapperUsesRoostContract() throws {
        let script = try resourceText("Muxy/Resources/scripts/roost-claude-wrapper.sh")
        let legacy = try resourceText("Muxy/Resources/scripts/muxy-claude-wrapper.sh")

        #expect(script.contains("ROOST_SOCKET_PATH"))
        #expect(script.contains("ROOST_PANE_ID"))
        #expect(script.contains("roost-claude-hook.sh"))
        #expect(legacy.contains("roost-claude-wrapper.sh"))
    }

    private func resourceText(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
