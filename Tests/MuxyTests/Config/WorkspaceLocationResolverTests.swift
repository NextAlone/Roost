import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("WorkspaceLocationResolver")
struct WorkspaceLocationResolverTests {
    @Test("empty config uses app support workspace directory")
    func fallbackDirectory() {
        let projectID = UUID()
        let url = WorkspaceLocationResolver.directory(
            projectID: projectID,
            projectPath: "/tmp/project",
            name: "feature",
            config: nil
        )
        #expect(url == MuxyFileStorage.worktreeDirectory(forProjectID: projectID, name: "feature"))
    }

    @Test("blank configured location falls back")
    func blankDirectory() {
        let projectID = UUID()
        let config = RoostConfig(defaultWorkspaceLocation: "  ")
        let url = WorkspaceLocationResolver.directory(
            projectID: projectID,
            projectPath: "/tmp/project",
            name: "feature",
            config: config
        )
        #expect(url == MuxyFileStorage.worktreeDirectory(forProjectID: projectID, name: "feature"))
    }

    @Test("relative location resolves against project path")
    func relativeDirectory() {
        let config = RoostConfig(defaultWorkspaceLocation: ".roost/workspaces")
        let url = WorkspaceLocationResolver.directory(
            projectID: UUID(),
            projectPath: "/tmp/project",
            name: "feature",
            config: config
        )
        #expect(url.path == "/tmp/project/.roost/workspaces/feature")
    }

    @Test("absolute location is used directly")
    func absoluteDirectory() {
        let config = RoostConfig(defaultWorkspaceLocation: "/tmp/roost-workspaces")
        let url = WorkspaceLocationResolver.directory(
            projectID: UUID(),
            projectPath: "/tmp/project",
            name: "feature",
            config: config
        )
        #expect(url.path == "/tmp/roost-workspaces/feature")
    }
}
