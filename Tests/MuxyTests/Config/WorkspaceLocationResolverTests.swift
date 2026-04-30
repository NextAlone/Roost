import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("WorkspaceLocationResolver")
struct WorkspaceLocationResolverTests {
    @Test("empty app config uses app support workspace directory")
    func fallbackDirectory() {
        let projectID = UUID()
        let url = WorkspaceLocationResolver.directory(
            projectID: projectID,
            projectPath: "/tmp/project",
            name: "feature",
            appConfig: nil
        )
        #expect(url == MuxyFileStorage.worktreeDirectory(forProjectID: projectID, name: "feature"))
    }

    @Test("blank app configured location falls back")
    func blankDirectory() {
        let projectID = UUID()
        let config = RoostConfig(defaultWorkspaceLocation: "  ")
        let url = WorkspaceLocationResolver.directory(
            projectID: projectID,
            projectPath: "/tmp/project",
            name: "feature",
            appConfig: config
        )
        #expect(url == MuxyFileStorage.worktreeDirectory(forProjectID: projectID, name: "feature"))
    }

    @Test("relative app location resolves against home directory")
    func relativeDirectory() {
        let config = RoostConfig(defaultWorkspaceLocation: "Documents/Repos/.workspaces")
        let url = WorkspaceLocationResolver.directory(
            projectID: UUID(),
            projectPath: "/tmp/project",
            name: "feature",
            appConfig: config
        )
        #expect(url.path == NSHomeDirectory() + "/Documents/Repos/.workspaces/feature")
    }

    @Test("absolute location is used directly")
    func absoluteDirectory() {
        let config = RoostConfig(defaultWorkspaceLocation: "/tmp/roost-workspaces")
        let url = WorkspaceLocationResolver.directory(
            projectID: UUID(),
            projectPath: "/tmp/project",
            name: "feature",
            appConfig: config
        )
        #expect(url.path == "/tmp/roost-workspaces/feature")
    }

    @Test("tilde location resolves against home directory")
    func tildeDirectory() {
        let config = RoostConfig(defaultWorkspaceLocation: "~/Documents/Repos/.workspaces")
        let url = WorkspaceLocationResolver.directory(
            projectID: UUID(),
            projectPath: "/tmp/project",
            name: "feature",
            appConfig: config
        )
        #expect(url.path == NSHomeDirectory() + "/Documents/Repos/.workspaces/feature")
    }
}
