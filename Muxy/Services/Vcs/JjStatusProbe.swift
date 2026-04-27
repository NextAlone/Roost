import Foundation
import MuxyShared

enum JjStatusProbeRawResult: Sendable {
    case success(hasEntries: Bool, hasConflicts: Bool)
    case failure
}

struct JjStatusProbe: VcsStatusProbe {
    private let probe: @Sendable (String) async -> Bool
    private let statusProbe: @Sendable (String) async -> JjStatusProbeRawResult

    init(
        probe: @escaping @Sendable (String) async -> Bool = Self.defaultProbe,
        statusJson: @escaping @Sendable (String) async -> JjStatusProbeRawResult = Self.defaultStatusJson
    ) {
        self.probe = probe
        self.statusProbe = statusJson
    }

    func hasUncommittedChanges(at worktreePath: String) async -> Bool {
        await probe(worktreePath)
    }

    func status(at worktreePath: String) async -> WorkspaceStatus {
        switch await statusProbe(worktreePath) {
        case .failure:
            return .unknown
        case let .success(hasEntries, hasConflicts):
            if hasConflicts { return .conflicted }
            return hasEntries ? .dirty : .clean
        }
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

    private static let defaultStatusJson: @Sendable (String) async -> JjStatusProbeRawResult = { worktreePath in
        do {
            let result = try await JjProcessRunner.run(
                repoPath: worktreePath,
                command: ["status"],
                snapshot: .ignore
            )
            guard result.status == 0 else { return .failure }
            let raw = String(data: result.stdout, encoding: .utf8) ?? ""
            let status = try JjStatusParser.parse(raw)
            return .success(hasEntries: !status.entries.isEmpty, hasConflicts: status.hasConflicts)
        } catch {
            return .failure
        }
    }
}
