import Foundation
import Testing

@testable import Roost

@Suite("HostdANSITextParser")
struct HostdANSITextParserTests {
    @Test("parses SGR foreground and reset spans")
    func parsesSGRForegroundAndResetSpans() {
        let parsed = HostdANSITextParser.parse("a\u{1B}[31mred\u{1B}[0m plain")

        #expect(parsed.plainText == "ared plain")
        #expect(parsed.runs == [
            HostdANSITextRun(
                range: NSRange(location: 1, length: 3),
                style: HostdANSITextStyle(foregroundColorIndex: 1)
            ),
        ])
    }

    @Test("parses bright colors and intensity")
    func parsesBrightColorsAndIntensity() {
        let parsed = HostdANSITextParser.parse("\u{1B}[1;92mok\u{1B}[22m!")

        #expect(parsed.plainText == "ok!")
        #expect(parsed.runs == [
            HostdANSITextRun(
                range: NSRange(location: 0, length: 2),
                style: HostdANSITextStyle(foregroundColorIndex: 10, isBold: true)
            ),
            HostdANSITextRun(
                range: NSRange(location: 2, length: 1),
                style: HostdANSITextStyle(foregroundColorIndex: 10)
            ),
        ])
    }

    @Test("parses 256 color foreground and background")
    func parses256ColorForegroundAndBackground() {
        let parsed = HostdANSITextParser.parse("\u{1B}[38;5;196;48;5;16mhot\u{1B}[49m!")

        #expect(parsed.plainText == "hot!")
        #expect(parsed.runs == [
            HostdANSITextRun(
                range: NSRange(location: 0, length: 3),
                style: HostdANSITextStyle(foregroundColorIndex: 196, backgroundColorIndex: 16)
            ),
            HostdANSITextRun(
                range: NSRange(location: 3, length: 1),
                style: HostdANSITextStyle(foregroundColorIndex: 196)
            ),
        ])
    }

    @Test("strips non SGR control sequences")
    func stripsNonSGRControlSequences() {
        let parsed = HostdANSITextParser.parse("a\u{1B}[2Kb\u{1B}]0;title\u{07}c")

        #expect(parsed.plainText == "abc")
        #expect(parsed.runs.isEmpty)
    }

    @Test("hides incomplete escape sequences")
    func hidesIncompleteEscapeSequences() {
        let parsed = HostdANSITextParser.parse("a\u{1B}[31")

        #expect(parsed.plainText == "a")
        #expect(parsed.runs.isEmpty)
    }
}
