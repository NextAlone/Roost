import Testing

@testable import Roost

@Suite("ClaudeCodeProvider")
struct ClaudeCodeProviderTests {
    @Test("installs lifecycle hooks for agent activity states")
    func installsLifecycleHooks() {
        #expect(ClaudeCodeProvider.installedEvents == ["SessionStart", "UserPromptSubmit", "Stop", "Notification"])
    }

    @Test("uses Roost hook script name")
    func usesRoostHookScriptName() {
        #expect(ClaudeCodeProvider().hookScriptName == "roost-claude-hook")
    }
}
