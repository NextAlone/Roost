import Foundation
import Testing

@Suite("Agent hook scripts")
struct AgentHookScriptTests {
    @Test("Claude hook emits activity-qualified socket types")
    func claudeHookTypes() throws {
        let script = try resourceText("Muxy/Resources/scripts/muxy-claude-hook.sh")
        #expect(script.contains("\"claude_hook:idle\""))
        #expect(script.contains("\"claude_hook:running\""))
        #expect(script.contains("\"claude_hook:needs_input\""))
        #expect(script.contains("\"claude_hook:completed\""))
    }

    @Test("Codex hook emits activity-qualified socket types")
    func codexHookTypes() throws {
        let script = try resourceText("Muxy/Resources/scripts/muxy-codex-hook.sh")
        #expect(script.contains("\"codex_hook:idle\""))
        #expect(script.contains("\"codex_hook:running\""))
        #expect(script.contains("\"codex_hook:needs_input\""))
        #expect(script.contains("\"codex_hook:completed\""))
    }

    @Test("Cursor hook emits activity-qualified socket types")
    func cursorHookTypes() throws {
        let script = try resourceText("Muxy/Resources/scripts/muxy-cursor-hook.sh")
        #expect(script.contains("\"cursor_hook:needs_input\""))
        #expect(script.contains("\"cursor_hook:completed\""))
    }

    @Test("OpenCode plugin emits idle activity")
    func openCodeIdleType() throws {
        let script = try resourceText("Muxy/Resources/scripts/opencode-muxy-plugin.js")
        #expect(script.contains("opencode:idle"))
    }

    private func resourceText(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
