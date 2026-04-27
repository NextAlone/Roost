import Foundation
import Testing

@testable import Roost

@Suite("VcsKind")
struct VcsKindTests {
    @Test("default is git")
    func defaultGit() {
        #expect(VcsKind.default == .git)
    }

    @Test("Codable round-trips")
    func codable() throws {
        let original: [VcsKind] = [.git, .jj]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([VcsKind].self, from: data)
        #expect(decoded == original)
    }

    @Test("decodes from string raw value")
    func decodesFromString() throws {
        let json = "[\"git\", \"jj\"]"
        let decoded = try JSONDecoder().decode([VcsKind].self, from: Data(json.utf8))
        #expect(decoded == [.git, .jj])
    }

    @Test("unknown raw value throws")
    func unknownThrows() {
        let json = "[\"hg\"]"
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode([VcsKind].self, from: Data(json.utf8))
        }
    }
}
