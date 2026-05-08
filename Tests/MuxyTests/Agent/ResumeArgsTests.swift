import Foundation
import MuxyShared
import Testing

@Suite("ResumeArgs metacharacter check")
struct ResumeArgsTests {
    @Test("plain args accepted")
    func plainArgsAccepted() {
        #expect(!ResumeArgs.containsShellMetacharacters("--resume abc-123"))
    }

    @Test("semicolon rejected")
    func semicolonRejected() {
        #expect(ResumeArgs.containsShellMetacharacters("--resume abc; rm -rf /"))
    }

    @Test("pipe rejected")
    func pipeRejected() {
        #expect(ResumeArgs.containsShellMetacharacters("--resume abc | tee"))
    }

    @Test("backtick rejected")
    func backtickRejected() {
        #expect(ResumeArgs.containsShellMetacharacters("--resume `whoami`"))
    }

    @Test("dollar paren rejected")
    func dollarParenRejected() {
        #expect(ResumeArgs.containsShellMetacharacters("--resume $(date)"))
    }

    @Test("newline rejected")
    func newlineRejected() {
        #expect(ResumeArgs.containsShellMetacharacters("--resume abc\nls"))
    }

    @Test("redirects rejected")
    func redirectsRejected() {
        #expect(ResumeArgs.containsShellMetacharacters("--resume abc > /tmp/x"))
        #expect(ResumeArgs.containsShellMetacharacters("--resume abc < /tmp/x"))
    }

    @Test("captureLooksValid for codex")
    func captureLooksValidForCodex() {
        #expect(ResumeArgs.captureLooksValid("codex resume abc-123", kind: .codex))
        #expect(!ResumeArgs.captureLooksValid("rogue resume abc", kind: .codex))
        #expect(!ResumeArgs.captureLooksValid("codex resume `evil`", kind: .codex))
    }
}
