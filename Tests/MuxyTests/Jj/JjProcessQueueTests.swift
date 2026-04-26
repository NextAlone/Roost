import Foundation
import Testing

@testable import Roost

@Suite("JjProcessQueue")
struct JjProcessQueueTests {
    @Test("mutating operations on same repo are serialized")
    func serializesMutating() async {
        let queue = JjProcessQueue()
        let log = Log()
        async let a: Void = queue.run(repoPath: "/repo", isMutating: true) {
            await log.append("a-start")
            try? await Task.sleep(nanoseconds: 50_000_000)
            await log.append("a-end")
        }
        async let b: Void = queue.run(repoPath: "/repo", isMutating: true) {
            await log.append("b-start")
            await log.append("b-end")
        }
        _ = await (a, b)
        let entries = await log.entries
        #expect(entries == ["a-start", "a-end", "b-start", "b-end"]
            || entries == ["b-start", "b-end", "a-start", "a-end"])
    }

    @Test("read operations run concurrently")
    func readsConcurrent() async {
        let queue = JjProcessQueue()
        let log = Log()
        async let a: Void = queue.run(repoPath: "/repo", isMutating: false) {
            await log.append("a-start")
            try? await Task.sleep(nanoseconds: 50_000_000)
            await log.append("a-end")
        }
        async let b: Void = queue.run(repoPath: "/repo", isMutating: false) {
            await log.append("b-start")
            await log.append("b-end")
        }
        _ = await (a, b)
        let entries = await log.entries
        #expect(entries.firstIndex(of: "b-start")! < entries.firstIndex(of: "a-end")!)
    }
}

actor Log {
    var entries: [String] = []
    func append(_ s: String) { entries.append(s) }
}
