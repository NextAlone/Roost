import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("JjDiffLoader")
struct JjDiffLoaderTests {
    @Test("stores parsed diff in cache on success")
    func storesParsedDiff() async throws {
        let cache = DiffCache()
        let patch = """
        diff --git a/x b/x
        --- a/x
        +++ b/x
        @@ -1,1 +1,2 @@
         a
        +b
        """
        let service = JjDiffService { _, _, _, _ in
            JjProcessResult(status: 0, stdout: Data(patch.utf8), stderr: "")
        }
        let request = JjDiffLoader.Request(
            repoPath: "/tmp/r",
            revset: "@",
            filePath: "x",
            forceFull: false
        )
        JjDiffLoader.load(request, cache: cache, service: service)
        try await waitUntil { cache.diff(for: "x") != nil || cache.error(for: "x") != nil }
        let diff = try #require(cache.diff(for: "x"))
        #expect(diff.additions == 1)
        #expect(diff.deletions == 0)
        #expect(diff.rows.isEmpty == false)
        #expect(diff.truncated == false)
    }

    @Test("stores error message on non-zero exit")
    func storesError() async throws {
        let cache = DiffCache()
        let service = JjDiffService { _, _, _, _ in
            JjProcessResult(status: 1, stdout: Data(), stderr: "no such file")
        }
        let request = JjDiffLoader.Request(
            repoPath: "/tmp/r",
            revset: "@",
            filePath: "missing",
            forceFull: false
        )
        JjDiffLoader.load(request, cache: cache, service: service)
        try await waitUntil { cache.error(for: "missing") != nil }
        let message = try #require(cache.error(for: "missing"))
        #expect(message.isEmpty == false)
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("waitUntil timed out")
    }
}
