import Foundation
import MuxyShared
import Testing

@Suite("AgentReloadCommandBuilder")
struct AgentReloadCommandBuilderTests {
    @Test("fresh always returns default command")
    func freshAlwaysReturnsDefaultCommand() {
        let preset = AgentPreset(
            kind: .claudeCode,
            defaultCommand: "claude --x",
            resumeCommandRegex: nil
        )
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "claude --resume abc",
            mode: .fresh
        )
        #expect(cmd == "claude --x")
    }

    @Test("claude appends args")
    func claudeAppendArgs() {
        let preset = AgentPreset(kind: .claudeCode, defaultCommand: "claude --x")
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "claude --resume abc",
            mode: .resume
        )
        #expect(cmd == "claude --x --resume abc")
    }

    @Test("claude mismatched capture falls back to default")
    func claudeMismatchedCaptureFallsBackToDefault() {
        let preset = AgentPreset(kind: .claudeCode, defaultCommand: "claude --x")
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "rogue --resume abc",
            mode: .resume
        )
        #expect(cmd == "claude --x")
    }

    @Test("claude metachar capture falls back to default")
    func claudeMetacharCaptureFallsBackToDefault() {
        let preset = AgentPreset(kind: .claudeCode, defaultCommand: "claude --x")
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "claude --resume abc; ls",
            mode: .resume
        )
        #expect(cmd == "claude --x")
    }

    @Test("codex uses captured verbatim")
    func codexUsesCapturedVerbatim() {
        let preset = AgentPreset(kind: .codex, defaultCommand: "codex --y")
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "codex resume abc-123",
            mode: .resume
        )
        #expect(cmd == "codex resume abc-123")
    }

    @Test("codex invalid captured falls back to default")
    func codexInvalidCapturedFallsBackToDefault() {
        let preset = AgentPreset(kind: .codex, defaultCommand: "codex --y")
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "rogue resume abc",
            mode: .resume
        )
        #expect(cmd == "codex --y")
    }

    @Test("notSupported falls back to default")
    func notSupportedFallsBackToDefault() {
        let preset = AgentPreset(kind: .geminiCli, defaultCommand: "gemini --z")
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "anything",
            mode: .resume
        )
        #expect(cmd == "gemini --z")
    }

    @Test("nil default command propagates as empty")
    func nilDefaultCommandPropagatesAsEmpty() {
        let preset = AgentPreset(kind: .terminal, defaultCommand: nil)
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: nil,
            mode: .fresh
        )
        #expect(cmd == "")
    }
}
