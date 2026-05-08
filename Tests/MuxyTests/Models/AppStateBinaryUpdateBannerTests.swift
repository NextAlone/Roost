import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("AppState.refreshBinaryUpdateBanner")
struct AppStateBinaryUpdateBannerTests {
    @Test("detects mtime increase")
    func detectsMtimeIncrease() throws {
        let rig = AppStateTestRig()
        let app = rig.makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        let pane = area.activeTab!.content.pane!
        app.workspaceRoots[key] = .tabArea(area)

        let bin = try createTempExecutable()
        defer { try? FileManager.default.removeItem(at: bin) }

        let pastMtime = Date(timeIntervalSinceNow: -120)
        try FileManager.default.setAttributes([.modificationDate: pastMtime], ofItemAtPath: bin.path)
        pane.agentBinaryPath = bin
        pane.agentBinaryMTime = pastMtime

        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: bin.path)

        app.refreshBinaryUpdateBanner(paneID: pane.id)

        #expect(app.pane(id: pane.id)?.binaryUpdateDetected == true)
    }

    @Test("no change does not flip flag")
    func noChangeDoesNotFlipFlag() throws {
        let rig = AppStateTestRig()
        let app = rig.makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        let pane = area.activeTab!.content.pane!
        app.workspaceRoots[key] = .tabArea(area)

        let bin = try createTempExecutable()
        defer { try? FileManager.default.removeItem(at: bin) }

        let mtime = Date()
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: bin.path)
        pane.agentBinaryPath = bin
        pane.agentBinaryMTime = mtime

        app.refreshBinaryUpdateBanner(paneID: pane.id)

        #expect(app.pane(id: pane.id)?.binaryUpdateDetected == false)
    }

    @Test("missing binary path does nothing")
    func missingPathDoesNothing() {
        let rig = AppStateTestRig()
        let app = rig.makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        let pane = area.activeTab!.content.pane!
        app.workspaceRoots[key] = .tabArea(area)

        pane.agentBinaryPath = nil
        pane.agentBinaryMTime = nil

        app.refreshBinaryUpdateBanner(paneID: pane.id)

        #expect(app.pane(id: pane.id)?.binaryUpdateDetected == false)
    }

    private func createTempExecutable() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-bin-\(UUID().uuidString)")
        try Data().write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
