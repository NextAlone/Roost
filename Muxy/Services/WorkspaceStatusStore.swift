import Foundation
import MuxyShared
import Observation

@MainActor
@Observable
final class WorkspaceStatusStore {
    private(set) var statuses: [UUID: WorkspaceStatus] = [:]
    private var watchers: [UUID: WorkspaceStatusWatcher] = [:]
    private let probeFactory: @Sendable (VcsKind) -> any VcsStatusProbe

    init(probeFactory: @escaping @Sendable (VcsKind) -> any VcsStatusProbe = VcsStatusProbeFactory.probe(for:)) {
        self.probeFactory = probeFactory
    }

    func status(forWorktreeID id: UUID) -> WorkspaceStatus {
        statuses[id] ?? .unknown
    }

    func refresh(worktreeID id: UUID, path: String, kind: VcsKind) async {
        let probe = probeFactory(kind)
        let result = await probe.status(at: path)
        statuses[id] = result
    }

    func startWatching(worktreeID id: UUID, path: String, kind: VcsKind) {
        guard watchers[id] == nil else { return }
        let watcher = WorkspaceStatusWatcher(directoryPath: path, vcsKind: kind) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refresh(worktreeID: id, path: path, kind: kind)
            }
        }
        watchers[id] = watcher
        Task { await refresh(worktreeID: id, path: path, kind: kind) }
    }

    func stopWatching(worktreeID id: UUID) {
        watchers.removeValue(forKey: id)
        statuses.removeValue(forKey: id)
    }

    func reconcile(activeIDs: Set<UUID>) {
        let staleWatched = Set(watchers.keys).subtracting(activeIDs)
        for id in staleWatched {
            stopWatching(worktreeID: id)
        }
        let staleStatuses = Set(statuses.keys).subtracting(activeIDs)
        for id in staleStatuses {
            statuses.removeValue(forKey: id)
        }
    }
}
