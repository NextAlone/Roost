import Foundation

@MainActor
enum JjDiffLoader {
    static let previewLineLimit = 20000

    struct Request {
        let repoPath: String
        let revset: String
        let filePath: String
        let forceFull: Bool
    }

    static func load(
        _ request: Request,
        cache: DiffCache,
        service: JjDiffService = JjDiffService()
    ) {
        cache.markLoading(request.filePath)
        let lineLimit = request.forceFull ? nil : previewLineLimit
        let task = Task { @MainActor in
            do {
                let raw = try await service.patch(
                    repoPath: request.repoPath,
                    revset: request.revset,
                    filePath: request.filePath,
                    lineLimit: lineLimit
                )
                guard !Task.isCancelled else { return }
                let parsed = GitDiffParser.parseRows(raw)
                let truncated = lineLimit != nil && countLines(raw) >= lineLimit!
                cache.store(
                    DiffCache.LoadedDiff(
                        rows: GitDiffParser.collapseContextRows(parsed.rows),
                        additions: parsed.additions,
                        deletions: parsed.deletions,
                        truncated: truncated
                    ),
                    for: request.filePath,
                    pinnedPaths: []
                )
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                cache.storeError(message, for: request.filePath)
            }
        }
        cache.registerTask(task, for: request.filePath)
    }

    private static func countLines(_ text: String) -> Int {
        text.reduce(into: 0) { count, ch in if ch == "\n" { count += 1 } }
    }
}
