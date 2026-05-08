import Foundation
import MuxyShared

struct JjDiffService: Sendable {
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

    func stat(repoPath: String, revset: String) async throws -> JjDiffStat {
        let result = try await runner(repoPath, ["diff", "--stat", "-r", revset], .ignore, nil)
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjDiffParser.parseStat(raw)
    }

    func summary(repoPath: String, revset: String) async throws -> [JjStatusEntry] {
        let result = try await runner(repoPath, ["diff", "--summary", "-r", revset], .ignore, nil)
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjStatusParser.parseSummaryEntries(raw)
    }

    func patch(
        repoPath: String,
        revset: String,
        filePath: String,
        lineLimit: Int?
    ) async throws -> String {
        let result = try await runner(
            repoPath,
            ["diff", "--git", "-r", revset, "--", filePath],
            .ignore,
            nil
        )
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        guard let lineLimit, lineLimit > 0 else { return raw }
        var seen = 0
        var endIndex = raw.startIndex
        while seen < lineLimit, endIndex < raw.endIndex {
            if let nl = raw[endIndex...].firstIndex(of: "\n") {
                endIndex = raw.index(after: nl)
                seen += 1
            } else {
                endIndex = raw.endIndex
                break
            }
        }
        return String(raw[..<endIndex])
    }
}
