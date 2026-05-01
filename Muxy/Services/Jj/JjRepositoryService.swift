import Foundation
import MuxyShared

struct JjRepositoryService: Sendable {
    private let runner: JjRunFn

    init(runner: @escaping JjRunFn = { repoPath, command, snapshot, atOp in
        try await JjProcessRunner.run(
            repoPath: repoPath,
            command: command,
            snapshot: snapshot,
            atOp: atOp
        )
    }) {
        self.runner = runner
    }

    func isJjRepo(repoPath: String) async throws -> Bool {
        let result = try await runner(repoPath, ["root"], .ignore, nil)
        return result.status == 0
    }

    func version() async throws -> JjVersion {
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

    func currentOpId(repoPath: String) async throws -> String {
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

    func show(repoPath: String, revset: String) async throws -> JjShowOutput {
        let result = try await runner(
            repoPath,
            ["show", "-r", revset, "-T", JjShowParser.template, "--stat"],
            .ignore,
            nil
        )
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjShowParser.parse(raw)
    }

    func log(repoPath: String, limit: Int = 30) async throws -> [JjLogEntry] {
        let result = try await runner(
            repoPath,
            ["log", "-n", "\(limit)", "-T", JjLogParser.template],
            .ignore,
            nil
        )
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return JjLogParser.parseLenient(raw)
    }
}
