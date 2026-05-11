import XCTest
@testable import Roost
@testable import MuxyShared

final class WorktreeCodableTests: XCTestCase {
    func testDecodesLegacyPayloadWithoutLastActiveAt() throws {
        let json = #"""
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "default",
            "path": "/tmp/p",
            "ownsBranch": false,
            "source": "muxy",
            "isPrimary": true,
            "createdAt": 0,
            "vcsKind": "git"
        }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Worktree.self, from: json)
        XCTAssertNil(decoded.lastActiveAt)
    }

    func testRoundTripsLastActiveAt() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var worktree = Worktree(name: "x", path: "/tmp/x", isPrimary: false)
        worktree.lastActiveAt = date
        let data = try JSONEncoder().encode(worktree)
        let decoded = try JSONDecoder().decode(Worktree.self, from: data)
        XCTAssertEqual(decoded.lastActiveAt, date)
    }
}
