import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("JjDiffViewerTabState")
struct JjDiffViewerTabStateTests {
    @Test("displayTitle returns last path component")
    func displayTitle() {
        let state = JjDiffViewerTabState(
            repoPath: "/tmp/r",
            revset: "@",
            filePath: "Sources/Foo/Bar.swift"
        )
        #expect(state.displayTitle == "Bar.swift")
    }

    @Test("init triggers a load via injected service")
    func loadsOnInit() async throws {
        let counter = CallCounter()
        let service = JjDiffService { _, _, _, _ in
            await counter.increment()
            return JjProcessResult(status: 0, stdout: Data("diff --git a/x b/x\n".utf8), stderr: "")
        }
        let state = JjDiffViewerTabState(
            repoPath: "/tmp/r",
            revset: "@",
            filePath: "x",
            diffService: service
        )
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if !state.diffCache.isLoading("x") { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let count = await counter.count
        #expect(count == 1)
    }

    @Test("refresh forceFull bypasses cache")
    func refreshForceFull() async throws {
        let counter = CallCounter()
        let service = JjDiffService { _, _, _, _ in
            await counter.increment()
            return JjProcessResult(status: 0, stdout: Data("diff --git a/x b/x\n".utf8), stderr: "")
        }
        let state = JjDiffViewerTabState(
            repoPath: "/tmp/r",
            revset: "@",
            filePath: "x",
            diffService: service
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        state.refresh(forceFull: true)
        try await Task.sleep(nanoseconds: 100_000_000)
        let count = await counter.count
        #expect(count >= 2)
    }
}

actor CallCounter {
    var count = 0
    func increment() { count += 1 }
}
