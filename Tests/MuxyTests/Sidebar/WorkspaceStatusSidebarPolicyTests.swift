import MuxyShared
import Testing

@testable import Roost

@Suite("WorkspaceStatus sidebar policy")
struct WorkspaceStatusSidebarPolicyTests {
    @Test("sidebar rows only surface blocking status")
    func sidebarRowsOnlySurfaceBlockingStatus() {
        #expect(WorkspaceStatus.clean.sidebarRowBadgeStatus == nil)
        #expect(WorkspaceStatus.unknown.sidebarRowBadgeStatus == nil)
        #expect(WorkspaceStatus.dirty.sidebarRowBadgeStatus == nil)
        #expect(WorkspaceStatus.conflicted.sidebarRowBadgeStatus == .conflicted)
    }
}
