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

    @Test("describe selected sends jj describe <revset> -m <message>")
    func describeSelected() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.describe(repoPath: "/tmp/wt", revset: "abc", message: "hello")
        #expect(recorder.commands == [["describe", "abc", "-m", "hello"]])
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

    @Test("new at sends jj new <revset>")
    func newAt() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.newAt(repoPath: "/tmp/wt", revset: "abc")
        #expect(recorder.commands == [["new", "abc"]])
    }

    @Test("new after sends jj new --insert-after <revset>")
    func newAfter() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.newAfter(repoPath: "/tmp/wt", revset: "abc")
        #expect(recorder.commands == [["new", "--insert-after", "abc"]])
    }

    @Test("new before sends jj new --insert-before <revset>")
    func newBefore() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.newBefore(repoPath: "/tmp/wt", revset: "abc")
        #expect(recorder.commands == [["new", "--insert-before", "abc"]])
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

    @Test("squash into sends jj squash --into <revset> --use-destination-message")
    func squashInto() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.squashInto(repoPath: "/tmp/wt", revset: "abc")
        #expect(recorder.commands == [["squash", "--into", "abc", "--use-destination-message"]])
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

    @Test("abandon selected sends jj abandon <revset>")
    func abandonSelected() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.abandon(repoPath: "/tmp/wt", revset: "abc")
        #expect(recorder.commands == [["abandon", "abc"]])
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

    @Test("duplicate selected sends jj duplicate <revset>")
    func duplicateSelected() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.duplicate(repoPath: "/tmp/wt", revset: "abc")
        #expect(recorder.commands == [["duplicate", "abc"]])
    }

    @Test("revert sends jj revert -r @ --insert-after @")
    func revert() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.revert(repoPath: "/tmp/wt")
        #expect(recorder.commands == [["revert", "-r", "@", "--insert-after", "@"]])
    }

    @Test("revert selected sends jj revert -r <revset> --insert-after @")
    func revertSelected() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.revert(repoPath: "/tmp/wt", revset: "abc")
        #expect(recorder.commands == [["revert", "-r", "abc", "--insert-after", "@"]])
    }

    @Test("edit sends jj edit <revset>")
    func edit() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.edit(repoPath: "/tmp/wt", revset: "abc")
        #expect(recorder.commands == [["edit", "abc"]])
    }

    @Test("edit immutable revision throws user-facing immutable error")
    func editImmutableRevision() async {
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, _, _, _ in
            JjProcessResult(status: 1, stdout: Data(), stderr: "Error: Revision abc is immutable and cannot be edited")
        })

        await #expect(throws: JjMutationError.immutableEdit(revset: "abc")) {
            try await service.edit(repoPath: "/tmp/wt", revset: "abc")
        }
        #expect(String(describing: JjMutationError.immutableEdit(revset: "abc")) == "Cannot edit abc because it is immutable.")
    }

    @Test("rebase working copy onto selected sends jj rebase -b @ -d <revset>")
    func rebaseWorkingCopyOnto() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.rebaseWorkingCopyOnto(repoPath: "/tmp/wt", revset: "abc")
        #expect(recorder.commands == [["rebase", "-b", "@", "-d", "abc"]])
    }

    @Test("restore operation restores repo state only")
    func restoreOperation() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.restoreOperation(repoPath: "/tmp/wt", id: "abc123")
        #expect(recorder.commands == [["op", "restore", "--what", "repo", "abc123"]])
    }

    @Test("resolve conflict with ours uses built-in ours tool")
    func resolveConflictOurs() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.resolveConflict(repoPath: "/tmp/wt", path: "README.md", tool: .ours)
        #expect(recorder.commands == [["resolve", "--tool", ":ours", "--", "README.md"]])
    }

    @Test("resolve conflict with theirs uses built-in theirs tool")
    func resolveConflictTheirs() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.resolveConflict(repoPath: "/tmp/wt", path: "README.md", tool: .theirs)
        #expect(recorder.commands == [["resolve", "--tool", ":theirs", "--", "README.md"]])
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
