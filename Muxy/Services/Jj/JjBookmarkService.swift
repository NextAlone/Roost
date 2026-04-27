import Foundation
import MuxyShared

struct JjBookmarkService: Sendable {
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

    func list(repoPath: String) async throws -> [JjBookmark] {
        let result = try await runner(
            repoPath,
            ["bookmark", "list", "--no-graph", "-T", JjBookmarkParser.template],
            .ignore,
            nil
        )
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjBookmarkParser.parse(raw)
    }

    func create(repoPath: String, name: String, revset: String?) async throws {
        var cmd: [String] = ["bookmark", "create", name]
        if let revset {
            cmd += ["-r", revset]
        }
        try await runMutating(repoPath: repoPath, command: cmd)
    }

    func setTarget(repoPath: String, name: String, revset: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["bookmark", "set", name, "-r", revset])
    }

    func forget(repoPath: String, name: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["bookmark", "forget", name])
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
