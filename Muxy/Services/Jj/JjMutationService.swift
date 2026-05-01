import Foundation
import MuxyShared

struct JjMutationService {
    private let queue: JjProcessQueue
    private let runner: JjRunFn

    init(queue: JjProcessQueue, runner: @escaping JjRunFn = { repoPath, command, snapshot, atOp in
        try await JjProcessRunner.run(
            repoPath: repoPath,
            command: command,
            snapshot: snapshot,
            atOp: atOp
        )
    }) {
        self.queue = queue
        self.runner = runner
    }

    func describe(repoPath: String, message: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["describe", "-m", message])
    }

    func describe(repoPath: String, revset: String, message: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["describe", revset, "-m", message])
    }

    func newChange(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["new"])
    }

    func newAt(repoPath: String, revset: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["new", revset])
    }

    func newAfter(repoPath: String, revset: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["new", "--insert-after", revset])
    }

    func newBefore(repoPath: String, revset: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["new", "--insert-before", revset])
    }

    func commit(repoPath: String, message: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["commit", "-m", message])
    }

    func squash(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["squash"])
    }

    func squashInto(repoPath: String, revset: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["squash", "--into", revset, "--use-destination-message"])
    }

    func abandon(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["abandon"])
    }

    func abandon(repoPath: String, revset: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["abandon", revset])
    }

    func duplicate(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["duplicate"])
    }

    func duplicate(repoPath: String, revset: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["duplicate", revset])
    }

    func revert(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["revert", "-r", "@", "--insert-after", "@"])
    }

    func revert(repoPath: String, revset: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["revert", "-r", revset, "--insert-after", "@"])
    }

    func edit(repoPath: String, revset: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["edit", revset])
    }

    func rebaseWorkingCopyOnto(repoPath: String, revset: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["rebase", "-b", "@", "-d", revset])
    }

    func restoreOperation(repoPath: String, id: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["op", "restore", "--what", "repo", id])
    }

    private func runMutating(repoPath: String, command: [String]) async throws {
        let runner = self.runner
        try await queue.run(repoPath: repoPath, isMutating: true) {
            let result = try await runner(repoPath, command, .allow, nil)
            if result.status != 0 {
                throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
            }
        }
    }
}
