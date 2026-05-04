import Testing

@testable import Roost

@Suite("CodexProvider")
struct CodexProviderTests {
    @Test("installs lifecycle hooks for agent activity states")
    func installsLifecycleHooks() {
        #expect(CodexProvider.installedEvents == ["SessionStart", "UserPromptSubmit", "Stop", "PermissionRequest"])
    }

    @Test("uses Roost hook script name")
    func usesRoostHookScriptName() {
        #expect(CodexProvider().hookScriptName == "roost-codex-hook")
    }
}
