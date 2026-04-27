import Foundation
import MuxyShared

public struct JjWorkspaceService: Sendable {
    private let queue: JjProcessQueue
    private let runner: JjRunFn

    public init(queue: JjProcessQueue, runner: @escaping JjRunFn = { repoPath, command, snapshot, atOp in
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

    public func list(repoPath: String) async throws -> [JjWorkspaceEntry] {
        let result = try await runner(repoPath, ["workspace", "list"], .ignore, nil)
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjWorkspaceParser.parse(raw)
    }

    public func add(repoPath: String, name: String, path: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["workspace", "add", "--name", name, path])
    }

    public func forget(repoPath: String, name: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["workspace", "forget", name])
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
