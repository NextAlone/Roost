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

    func newChange(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["new"])
    }

    func commit(repoPath: String, message: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["commit", "-m", message])
    }

    func squash(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["squash"])
    }

    func abandon(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["abandon"])
    }

    func duplicate(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["duplicate"])
    }

    func backout(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["backout", "-r", "@"])
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
