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

    @Test("refresh coalesces concurrent worktree probes")
    func refreshCoalescesConcurrentProbe() async {
        let id = UUID()
        let probe = CountingProbe(status: .dirty)
        let store = WorkspaceStatusStore(probeFactory: { _ in probe })

        async let first: Void = store.refresh(worktreeID: id, path: "/tmp/wt", kind: .jj)
        async let second: Void = store.refresh(worktreeID: id, path: "/tmp/wt", kind: .jj)
        _ = await (first, second)

        #expect(await probe.callCount() == 1)
        #expect(store.status(forWorktreeID: id) == .dirty)
    }
}

private struct StubProbe: VcsStatusProbe {
    let status: WorkspaceStatus
    func hasUncommittedChanges(at worktreePath: String) async -> Bool {
        status == .dirty || status == .conflicted
    }
    func status(at worktreePath: String) async -> WorkspaceStatus { status }
}

private actor CountingProbe: VcsStatusProbe {
    private let statusValue: WorkspaceStatus
    private var calls = 0

    init(status: WorkspaceStatus) {
        statusValue = status
    }

    func hasUncommittedChanges(at worktreePath: String) async -> Bool {
        statusValue == .dirty || statusValue == .conflicted
    }

    func status(at worktreePath: String) async -> WorkspaceStatus {
        calls += 1
        try? await Task.sleep(nanoseconds: 30_000_000)
        return statusValue
    }

    func callCount() -> Int {
        calls
    }
}
