import Foundation
import Testing

@testable import Roost

@Suite("Worktree tolerant decode")
struct WorktreeTolerantDecodeTests {
    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    @Test("decodes v1 record (no vcsKind, no currentChangeId)")
    func v1Decode() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789012",
          "name": "main",
          "path": "/Users/me/repo",
          "branch": "main",
          "ownsBranch": false,
          "source": "muxy",
          "isPrimary": true,
          "createdAt": 776073600
        }
        """
        let decoded = try makeDecoder().decode(Worktree.self, from: Data(json.utf8))
        #expect(decoded.vcsKind == .git)
        #expect(decoded.currentChangeId == nil)
        #expect(decoded.name == "main")
        #expect(decoded.branch == "main")
    }

    @Test("decodes v2 record with vcsKind and currentChangeId")
    func v2Decode() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789012",
          "name": "feat-x",
          "path": "/Users/me/repo/.worktrees/feat-x",
          "branch": "feat-x",
          "ownsBranch": true,
          "source": "muxy",
          "isPrimary": false,
          "createdAt": 776073600,
          "vcsKind": "jj",
          "currentChangeId": "vk[rwwqlnruos]"
        }
        """
        let decoded = try makeDecoder().decode(Worktree.self, from: Data(json.utf8))
        #expect(decoded.vcsKind == .jj)
        #expect(decoded.currentChangeId == "vk[rwwqlnruos]")
    }

    @Test("encode v2 then decode round-trips")
    func roundTrip() throws {
        let original = Worktree(
            name: "feat",
            path: "/repo/.worktrees/feat",
            branch: "feat",
            ownsBranch: true,
            source: .muxy,
            isPrimary: false,
            vcsKind: .jj,
            currentChangeId: "abc123"
        )
        let data = try makeEncoder().encode(original)
        let decoded = try makeDecoder().decode(Worktree.self, from: data)
        #expect(decoded.vcsKind == .jj)
        #expect(decoded.currentChangeId == "abc123")
        #expect(decoded.branch == "feat")
    }
}
