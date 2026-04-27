import Foundation
import MuxyShared

enum GitStatusProbeRawResult {
    case success(lines: [String])
    case failure
}

struct GitStatusProbe: VcsStatusProbe {
    private let porcelain: @Sendable (String) async -> GitStatusProbeRawResult

    init(porcelainJson: @escaping @Sendable (String) async -> GitStatusProbeRawResult = Self.defaultPorcelain) {
        self.porcelain = porcelainJson
    }

    func hasUncommittedChanges(at worktreePath: String) async -> Bool {
        await GitWorktreeService.shared.hasUncommittedChanges(worktreePath: worktreePath)
    }

    func status(at worktreePath: String) async -> WorkspaceStatus {
        switch await porcelain(worktreePath) {
        case .failure:
            return .unknown
        case let .success(lines):
            let conflicted = lines.contains { line in
                guard line.count >= 2 else { return false }
                let prefix = String(line.prefix(2))
                return Self.conflictPrefixes.contains(prefix)
            }
            if conflicted { return .conflicted }
            return lines.isEmpty ? .clean : .dirty
        }
    }

    private static let conflictPrefixes: Set<String> = [
        "UU", "AA", "DD", "AU", "UA", "UD", "DU",
    ]

    private static let defaultPorcelain: @Sendable (String) async -> GitStatusProbeRawResult = { worktreePath in
        do {
            let lines = try await GitWorktreeService.shared.statusPorcelainLines(at: worktreePath)
            return .success(lines: lines)
        } catch {
            return .failure
        }
    }
}
