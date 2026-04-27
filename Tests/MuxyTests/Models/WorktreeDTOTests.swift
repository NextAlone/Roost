import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("WorktreeDTO vcsKind")
struct WorktreeDTOTests {
    @Test("toDTO carries vcsKind from Worktree")
    func toDTOPasses() {
        let worktree = Worktree(
            name: "feat",
            path: "/repo/.worktrees/feat",
            branch: "feat",
            ownsBranch: true,
            source: .muxy,
            isPrimary: false,
            createdAt: Date(timeIntervalSince1970: 776073600),
            vcsKind: .jj,
            currentChangeId: "abc"
        )
        let dto = worktree.toDTO()
        #expect(dto.vcsKind == .jj)
        #expect(dto.branch == "feat")
        #expect(dto.isPrimary == false)
    }

    @Test("decodes legacy DTO without vcsKind as .git")
    func legacyDecode() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "main",
          "path": "/Users/me/repo",
          "isPrimary": true,
          "createdAt": 776073600
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let dto = try decoder.decode(WorktreeDTO.self, from: Data(json.utf8))
        #expect(dto.vcsKind == .git)
    }

    @Test("encode + decode round-trips vcsKind")
    func roundTrip() throws {
        let original = WorktreeDTO(
            id: UUID(),
            name: "feat",
            path: "/repo/.worktrees/feat",
            branch: "feat",
            isPrimary: false,
            canBeRemoved: true,
            createdAt: Date(timeIntervalSince1970: 776073600),
            vcsKind: .jj
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorktreeDTO.self, from: data)
        #expect(decoded.vcsKind == .jj)
        #expect(decoded.name == original.name)
    }
}
