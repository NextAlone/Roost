import Foundation
import MuxyShared
import Observation

@MainActor
@Observable
final class SessionHistoryStore {
    private(set) var records: [SessionRecord] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    private let client: (any RoostHostdClient)?

    init(client: (any RoostHostdClient)? = nil) {
        self.client = client
    }

    func refresh() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await client.listAllSessions()
            records = result
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func prune() async {
        guard let client else { return }
        do {
            try await client.pruneExited()
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
