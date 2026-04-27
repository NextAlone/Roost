import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("WorkspaceStatusStore")
struct WorkspaceStatusStoreTests {
    @Test("status defaults to .unknown for unknown id")
    func defaultUnknown() {
        let store = WorkspaceStatusStore()
        #expect(store.status(forWorktreeID: UUID()) == .unknown)
    }

    @Test("refresh sets status from probe")
    func refreshUsesProbe() async {
        let id = UUID()
        let probe = StubProbe(status: .conflicted)
        let store = WorkspaceStatusStore(probeFactory: { _ in probe })
        await store.refresh(worktreeID: id, path: "/tmp/wt", kind: .jj)
        #expect(store.status(forWorktreeID: id) == .conflicted)
    }

    @Test("reconcile drops removed worktrees")
    func reconcileDrops() async {
        let id = UUID()
        let probe = StubProbe(status: .dirty)
        let store = WorkspaceStatusStore(probeFactory: { _ in probe })
        await store.refresh(worktreeID: id, path: "/tmp/wt", kind: .jj)
        store.reconcile(activeIDs: [])
        #expect(store.status(forWorktreeID: id) == .unknown)
    }
}

private struct StubProbe: VcsStatusProbe {
    let status: WorkspaceStatus
    func hasUncommittedChanges(at worktreePath: String) async -> Bool {
        status == .dirty || status == .conflicted
    }
    func status(at worktreePath: String) async -> WorkspaceStatus { status }
}
