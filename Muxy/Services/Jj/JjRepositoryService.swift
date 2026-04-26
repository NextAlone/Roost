import Foundation
import MuxyShared

public typealias JjRunFn = @Sendable (
    _ repoPath: String,
    _ command: [String],
    _ snapshot: JjSnapshotPolicy,
    _ atOp: String?
) async throws -> JjProcessResult

public struct JjRepositoryService: Sendable {
    private let runner: JjRunFn

    public init(runner: @escaping JjRunFn = { repoPath, command, snapshot, atOp in
        try await JjProcessRunner.run(
            repoPath: repoPath,
            command: command,
            snapshot: snapshot,
            atOp: atOp
        )
    }) {
        self.runner = runner
    }

    public func isJjRepo(path: String) async throws -> Bool {
        let result = try await runner(path, ["root"], .ignore, nil)
        return result.status == 0
    }

    public func version(path: String) async throws -> JjVersion {
        let result = try await runner(path, ["--version"], .ignore, nil)
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjVersion.parse(raw)
    }

    public func currentOpId(path: String) async throws -> String {
        let result = try await runner(
            path,
            ["op", "log", "-n", "1", "--no-graph", "-T", JjOpLogParser.template],
            .ignore,
            nil
        )
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        let ops = try JjOpLogParser.parse(raw)
        guard let first = ops.first else {
            throw JjProcessError.nonZeroExit(status: 0, stderr: "empty op log")
        }
        return first.id
    }
}
