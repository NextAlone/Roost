import Foundation
import MuxyShared
import Observation

@MainActor
@Observable
final class JjPanelState {
    let repoPath: String
    private(set) var snapshot: JjPanelSnapshot?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?
    private(set) var activeChangesRevset: String = ""

    private let loader: JjPanelLoader

    init(repoPath: String, loader: JjPanelLoader = JjPanelLoader()) {
        self.repoPath = repoPath
        self.loader = loader
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await loader.load(repoPath: repoPath, changesRevset: normalizedChangesRevset)
            snapshot = result
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func applyChangesRevset(_ revset: String) async {
        activeChangesRevset = revset.trimmingCharacters(in: .whitespacesAndNewlines)
        await refresh()
    }

    func resetChangesRevset() async {
        activeChangesRevset = ""
        await refresh()
    }

    private var normalizedChangesRevset: String? {
        activeChangesRevset.isEmpty ? nil : activeChangesRevset
    }
}
