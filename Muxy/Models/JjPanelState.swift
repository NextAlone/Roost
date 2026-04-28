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

    private let loader: JjPanelLoader

    init(repoPath: String, loader: JjPanelLoader = JjPanelLoader()) {
        self.repoPath = repoPath
        self.loader = loader
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await loader.load(repoPath: repoPath)
            snapshot = result
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
