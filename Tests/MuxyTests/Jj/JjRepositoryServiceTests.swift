import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjRepositoryService")
struct JjRepositoryServiceTests {
    @Test("isJjRepo true on success")
    func isRepoTrue() async throws {
        let svc = JjRepositoryService { _, _, _, _ in
            JjProcessResult(status: 0, stdout: Data("/repo\n".utf8), stderr: "")
        }
        #expect(try await svc.isJjRepo(repoPath: "/repo"))
    }

    @Test("isJjRepo false on non-zero exit")
    func isRepoFalse() async throws {
        let svc = JjRepositoryService { _, _, _, _ in
            JjProcessResult(status: 1, stdout: Data(), stderr: "no jj repo")
        }
        #expect(try await svc.isJjRepo(repoPath: "/repo") == false)
    }

    @Test("currentOpId parses op log")
    func currentOp() async throws {
        let svc = JjRepositoryService { _, _, _, _ in
            JjProcessResult(
                status: 0,
                stdout: Data("abc1234\t2026-04-27T10:15:30+00:00\tcommit\n".utf8),
                stderr: ""
            )
        }
        let op = try await svc.currentOpId(repoPath: "/repo")
        #expect(op == "abc1234")
    }
}
