import Foundation
import MuxyShared

struct JjPanelLoader: Sendable {
    private let showLoader: @Sendable (String) async throws -> JjShowOutput
    private let statusLoader: @Sendable (String) async throws -> JjStatus
    private let summaryLoader: @Sendable (String, String) async throws -> [JjStatusEntry]

    init(
        showLoader: @escaping @Sendable (String) async throws -> JjShowOutput = Self.defaultShow,
        statusLoader: @escaping @Sendable (String) async throws -> JjStatus = Self.defaultStatus,
        summaryLoader: @escaping @Sendable (String, String) async throws -> [JjStatusEntry] = Self.defaultSummary
    ) {
        self.showLoader = showLoader
        self.statusLoader = statusLoader
        self.summaryLoader = summaryLoader
    }

    func load(repoPath: String) async throws -> JjPanelSnapshot {
        let show = try await showLoader(repoPath)
        let status = try await statusLoader(repoPath)
        let parentDiff = (try? await summaryLoader(repoPath, "@-")) ?? []
        return JjPanelSnapshot(show: show, parentDiff: parentDiff, status: status)
    }

    private static let defaultShow: @Sendable (String) async throws -> JjShowOutput = { repoPath in
        try await JjRepositoryService().show(repoPath: repoPath, revset: "@")
    }

    private static let defaultStatus: @Sendable (String) async throws -> JjStatus = { repoPath in
        let result = try await JjProcessRunner.run(
            repoPath: repoPath,
            command: ["status"],
            snapshot: .ignore,
            atOp: nil
        )
        guard result.status == 0 else {
            throw JjPanelLoaderError.statusFailed(stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjStatusParser.parse(raw)
    }

    private static let defaultSummary: @Sendable (String, String) async throws -> [JjStatusEntry] = { repoPath, revset in
        try await JjDiffService().summary(repoPath: repoPath, revset: revset)
    }
}

enum JjPanelLoaderError: Error, Sendable {
    case statusFailed(stderr: String)
}
