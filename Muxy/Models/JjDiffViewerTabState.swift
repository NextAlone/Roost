import Foundation

@MainActor
@Observable
final class JjDiffViewerTabState: Identifiable {
    let id = UUID()
    let repoPath: String
    let revset: String
    let filePath: String
    let diffCache = DiffCache()
    var mode: VCSTabState.ViewMode = .unified

    var projectPath: String { repoPath }
    var displayTitle: String { (filePath as NSString).lastPathComponent }

    private let diffService: JjDiffService

    init(
        repoPath: String,
        revset: String,
        filePath: String,
        diffService: JjDiffService = JjDiffService()
    ) {
        self.repoPath = repoPath
        self.revset = revset
        self.filePath = filePath
        self.diffService = diffService
        load(forceFull: false)
    }

    func refresh(forceFull: Bool) {
        load(forceFull: forceFull)
    }

    private func load(forceFull: Bool) {
        if !forceFull, diffCache.hasDiff(for: filePath) {
            diffCache.touch(filePath)
            return
        }
        JjDiffLoader.load(
            JjDiffLoader.Request(
                repoPath: repoPath,
                revset: revset,
                filePath: filePath,
                forceFull: forceFull
            ),
            cache: diffCache,
            service: diffService
        )
    }
}
