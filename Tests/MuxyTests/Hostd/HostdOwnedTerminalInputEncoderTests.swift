import AppKit
import Foundation
import Testing

@testable import Roost

@Suite("HostdOwnedTerminalInputEncoder")
struct HostdOwnedTerminalInputEncoderTests {
    @Test("encodes printable text")
    func encodesPrintableText() {
        #expect(HostdOwnedTerminalInputEncoder.data(characters: "abc", keyCode: 0) == Data("abc".utf8))
    }

    @Test("maps control-c to interrupt signal")
    func mapsControlCToInterruptSignal() {
        #expect(HostdOwnedTerminalInputEncoder.action(
            characters: "\u{3}",
            keyCode: 8,
            modifierFlags: .control
        ) == .signal(.interrupt))
    }

    @Test("encodes terminal control keys")
    func encodesTerminalControlKeys() {
        #expect(HostdOwnedTerminalInputEncoder.data(characters: nil, keyCode: 36) == Data([13]))
        #expect(HostdOwnedTerminalInputEncoder.data(characters: nil, keyCode: 51) == Data([127]))
        #expect(HostdOwnedTerminalInputEncoder.data(characters: nil, keyCode: 53) == Data([27]))
        #expect(HostdOwnedTerminalInputEncoder.data(characters: nil, keyCode: 126) == Data("\u{1B}[A".utf8))
        #expect(HostdOwnedTerminalInputEncoder.data(characters: nil, keyCode: 125) == Data("\u{1B}[B".utf8))
        #expect(HostdOwnedTerminalInputEncoder.data(characters: nil, keyCode: 124) == Data("\u{1B}[C".utf8))
        #expect(HostdOwnedTerminalInputEncoder.data(characters: nil, keyCode: 123) == Data("\u{1B}[D".utf8))
    }

    @Test("ignores command shortcuts")
    func ignoresCommandShortcuts() {
        #expect(HostdOwnedTerminalInputEncoder.data(
            characters: "c",
            keyCode: 8,
            modifierFlags: .command
        ) == nil)
    }
}
