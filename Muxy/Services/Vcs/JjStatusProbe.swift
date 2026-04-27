import Foundation
import MuxyShared

struct JjStatusProbe: VcsStatusProbe {
    private let probe: @Sendable (String) async -> Bool

    init(probe: @escaping @Sendable (String) async -> Bool = Self.defaultProbe) {
        self.probe = probe
    }

    func hasUncommittedChanges(at worktreePath: String) async -> Bool {
        await probe(worktreePath)
    }

    private static let defaultProbe: @Sendable (String) async -> Bool = { worktreePath in
        do {
            let result = try await JjProcessRunner.run(
                repoPath: worktreePath,
                command: ["status"],
                snapshot: .ignore
            )
            guard result.status == 0 else { return false }
            let raw = String(data: result.stdout, encoding: .utf8) ?? ""
            let status = try JjStatusParser.parse(raw)
            return !status.entries.isEmpty || status.hasConflicts
        } catch {
            return false
        }
    }
}
