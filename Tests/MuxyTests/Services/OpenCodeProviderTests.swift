import Testing

@testable import Roost

@Suite("OpenCodeProvider")
struct OpenCodeProviderTests {
    @Test("uses Roost plugin file name")
    func usesRoostPluginFileName() {
        #expect(OpenCodeProvider.pluginFileNameForTests == "roost-notify.js")
        #expect(OpenCodeProvider.pluginScriptNameForTests == "opencode-roost-plugin.js")
    }
}
