import Foundation
import MuxyShared

struct JjConflictsService: Sendable {
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

    func list(repoPath: String) async throws -> [JjConflict] {
        let result = try await runner(
            repoPath,
            ["resolve", "--list"],
            .ignore,
            nil
        )
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return JjConflictParser.parse(raw)
    }
}
