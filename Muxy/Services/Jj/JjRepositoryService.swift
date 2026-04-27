import Foundation
import MuxyShared

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

    public func isJjRepo(repoPath: String) async throws -> Bool {
        let result = try await runner(repoPath, ["root"], .ignore, nil)
        return result.status == 0
    }

    public func version() async throws -> JjVersion {
        guard let exec = JjProcessRunner.resolveExecutable() else {
            throw JjProcessError.launchFailed("jj not found on PATH")
        }
        let result = try await JjProcessRunner.runRaw(executable: exec, arguments: ["--version"])
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjVersion.parse(raw)
    }

    public func currentOpId(repoPath: String) async throws -> String {
        let result = try await runner(
            repoPath,
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
