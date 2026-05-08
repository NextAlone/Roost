import Foundation
import MuxyShared
import Testing

@Suite("AgentPreset compiled regex")
struct AgentPresetRegexCacheTests {
    @Test("valid regex compiles and caches")
    func validRegexCompilesAndCaches() {
        let preset = AgentPreset(
            kind: .claudeCode,
            defaultCommand: "claude",
            resumeCommandRegex: #"(?m)^claude.*$"#
        )
        #expect(preset.compiledResumeRegex() != nil)
    }

    @Test("nil override falls back to default")
    func nilOverrideFallsBackToDefault() {
        let preset = AgentPreset(kind: .claudeCode, defaultCommand: "claude")
        #expect(preset.compiledResumeRegex() != nil)
    }

    @Test("invalid regex returns nil")
    func invalidRegexReturnsNil() {
        let preset = AgentPreset(
            kind: .claudeCode,
            defaultCommand: "claude",
            resumeCommandRegex: "(unclosed"
        )
        #expect(preset.compiledResumeRegex() == nil)
    }

    @Test("notSupported kind returns nil")
    func notSupportedReturnsNil() {
        let preset = AgentPreset(kind: .geminiCli, defaultCommand: "gemini")
        #expect(preset.compiledResumeRegex() == nil)
    }
}
