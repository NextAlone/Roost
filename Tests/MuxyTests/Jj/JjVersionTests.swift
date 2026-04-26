import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjVersion parsing")
struct JjVersionTests {
    @Test("parses standard release line")
    func parsesRelease() throws {
        let v = try JjVersion.parse("jj 0.20.0\n")
        #expect(v == JjVersion(major: 0, minor: 20, patch: 0))
    }

    @Test("parses dev suffix")
    func parsesDev() throws {
        let v = try JjVersion.parse("jj 0.21.0-dev (abc1234)\n")
        #expect(v == JjVersion(major: 0, minor: 21, patch: 0))
    }

    @Test("rejects malformed input")
    func rejectsGarbage() {
        #expect(throws: (any Error).self) {
            _ = try JjVersion.parse("not a version")
        }
    }

    @Test("minimum check")
    func minimum() throws {
        #expect(JjVersion.minimumSupported == JjVersion(major: 0, minor: 20, patch: 0))
        #expect(try JjVersion.parse("jj 0.19.0\n") < JjVersion.minimumSupported)
        #expect(try JjVersion.parse("jj 0.20.0\n") >= JjVersion.minimumSupported)
        #expect(try JjVersion.parse("jj 1.0.0\n") >= JjVersion.minimumSupported)
    }
}
