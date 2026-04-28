import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("JjMutationService")
struct JjMutationServiceTests {
    private final class CommandRecorder: @unchecked Sendable {
        var commands: [[String]] = []
        let lock = NSLock()
        func record(_ cmd: [String]) {
            lock.lock(); defer { lock.unlock() }
            commands.append(cmd)
        }
    }

    @Test("describe sends jj describe -m <message>")
    func describe() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.describe(repoPath: "/tmp/wt", message: "hello world")
        #expect(recorder.commands == [["describe", "-m", "hello world"]])
    }

    @Test("new sends jj new")
    func newChange() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.newChange(repoPath: "/tmp/wt")
        #expect(recorder.commands == [["new"]])
    }

    @Test("commit sends jj commit -m <message>")
    func commitChange() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.commit(repoPath: "/tmp/wt", message: "feat: x")
        #expect(recorder.commands == [["commit", "-m", "feat: x"]])
    }

    @Test("squash sends jj squash")
    func squash() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.squash(repoPath: "/tmp/wt")
        #expect(recorder.commands == [["squash"]])
    }

    @Test("abandon sends jj abandon")
    func abandon() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.abandon(repoPath: "/tmp/wt")
        #expect(recorder.commands == [["abandon"]])
    }

    @Test("duplicate sends jj duplicate")
    func duplicate() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.duplicate(repoPath: "/tmp/wt")
        #expect(recorder.commands == [["duplicate"]])
    }

    @Test("backout sends jj backout -r @")
    func backout() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.backout(repoPath: "/tmp/wt")
        #expect(recorder.commands == [["backout", "-r", "@"]])
    }

    @Test("non-zero exit throws")
    func nonZeroExit() async {
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, _, _, _ in
            JjProcessResult(status: 1, stdout: Data(), stderr: "boom")
        })
        await #expect(throws: (any Error).self) {
            try await service.describe(repoPath: "/tmp/wt", message: "x")
        }
    }
}
