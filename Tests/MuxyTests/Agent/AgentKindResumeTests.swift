import Foundation
import MuxyShared
import Testing

@Suite("AgentKind resume metadata")
struct AgentKindResumeTests {
    @Test
    func claudeRegexMatchesMockedTail() throws {
        let text = "some output\nclaude --resume abc-123\nmore noise\n"
        let pattern = try #require(AgentKind.claudeCode.defaultResumeRegex)
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        #expect(regex.firstMatch(in: text, range: range) != nil)
    }

    @Test
    func codexRegexMatchesMockedTail() throws {
        let text = "running...\ncodex resume xyz-456\n"
        let pattern = try #require(AgentKind.codex.defaultResumeRegex)
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        #expect(regex.firstMatch(in: text, range: range) != nil)
    }

    @Test
    func agentsWithoutResumeReturnNil() {
        #expect(AgentKind.geminiCli.defaultResumeRegex == nil)
        #expect(AgentKind.openCode.defaultResumeRegex == nil)
        #expect(AgentKind.terminal.defaultResumeRegex == nil)
    }

    @Test
    func expectedBinaryNames() {
        #expect(AgentKind.claudeCode.expectedBinaryName == "claude")
        #expect(AgentKind.codex.expectedBinaryName == "codex")
        #expect(AgentKind.geminiCli.expectedBinaryName == "gemini")
        #expect(AgentKind.openCode.expectedBinaryName == "opencode")
        #expect(AgentKind.terminal.expectedBinaryName == nil)
    }
}
