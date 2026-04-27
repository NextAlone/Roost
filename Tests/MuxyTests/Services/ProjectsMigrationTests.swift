import Foundation
import Testing

@testable import Roost

@Suite("ProjectsPersistence schema migration")
struct ProjectsMigrationTests {
    @Test("reads v1 bare array")
    func readsV1() throws {
        let json = """
        [
          {"id":"11111111-1111-1111-1111-111111111111","name":"Repo","path":"/Users/me/repo","sortOrder":0,"createdAt":712345678.0}
        ]
        """
        let payload = try ProjectsPersistencePayload.decode(Data(json.utf8))
        #expect(payload.schemaVersion == 1)
        #expect(payload.projects.count == 1)
        #expect(payload.projects[0].name == "Repo")
    }

    @Test("reads v2 envelope")
    func readsV2() throws {
        let json = """
        {
          "schemaVersion": 2,
          "projects": [
            {"id":"11111111-1111-1111-1111-111111111111","name":"Repo","path":"/Users/me/repo","sortOrder":0,"createdAt":712345678.0}
          ]
        }
        """
        let payload = try ProjectsPersistencePayload.decode(Data(json.utf8))
        #expect(payload.schemaVersion == 2)
        #expect(payload.projects.count == 1)
    }

    @Test("writer emits v2 envelope")
    func writesV2() throws {
        let payload = ProjectsPersistencePayload(
            schemaVersion: ProjectsPersistencePayload.currentVersion,
            projects: []
        )
        let data = try payload.encode()
        let raw = String(data: data, encoding: .utf8) ?? ""
        #expect(raw.contains("\"schemaVersion\""))
        #expect(raw.contains("\(ProjectsPersistencePayload.currentVersion)"))
    }

    @Test("future version reads as tolerant fallback")
    func futureVersionTolerant() throws {
        let json = """
        {
          "schemaVersion": 999,
          "projects": [
            {"id":"11111111-1111-1111-1111-111111111111","name":"Repo","path":"/Users/me/repo","sortOrder":0,"createdAt":712345678.0}
          ]
        }
        """
        let payload = try ProjectsPersistencePayload.decode(Data(json.utf8))
        #expect(payload.schemaVersion == 999)
        #expect(payload.projects.count == 1)
    }

    @Test("v1 projects + worktrees round-trip through v2 with defaults")
    func endToEndV1RoundTrip() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("muxy-migration-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let projectsURL = tmp.appendingPathComponent("projects.json")
        let v1ProjectsJson = """
        [
          {"id":"11111111-1111-1111-1111-111111111111","name":"Repo","path":"/Users/me/repo","createdAt":712345678.0,"sortOrder":0}
        ]
        """
        try v1ProjectsJson.data(using: .utf8)!.write(to: projectsURL)

        let worktreesDirURL = tmp.appendingPathComponent("worktrees")
        try fm.createDirectory(at: worktreesDirURL, withIntermediateDirectories: true)
        let worktreesURL = worktreesDirURL.appendingPathComponent("11111111-1111-1111-1111-111111111111.json")
        let v1WorktreesJson = """
        [
          {
            "id": "22222222-2222-2222-2222-222222222222",
            "name": "main",
            "path": "/Users/me/repo",
            "branch": "main",
            "ownsBranch": false,
            "source": "muxy",
            "isPrimary": true,
            "createdAt": 712345678.0
          }
        ]
        """
        try v1WorktreesJson.data(using: .utf8)!.write(to: worktreesURL)

        let projectsData = try Data(contentsOf: projectsURL)
        let projectsPayload = try ProjectsPersistencePayload.decode(projectsData)
        #expect(projectsPayload.schemaVersion == 1)
        #expect(projectsPayload.projects.count == 1)

        let worktreesData = try Data(contentsOf: worktreesURL)
        let worktrees = try JSONDecoder().decode([Worktree].self, from: worktreesData)
        #expect(worktrees.count == 1)
        #expect(worktrees[0].vcsKind == .git)
        #expect(worktrees[0].currentChangeId == nil)
        #expect(worktrees[0].name == "main")

        let upgraded = ProjectsPersistencePayload(
            schemaVersion: ProjectsPersistencePayload.currentVersion,
            projects: projectsPayload.projects
        )
        let upgradedData = try upgraded.encode()
        let parsed = try JSONSerialization.jsonObject(with: upgradedData) as? [String: Any]
        #expect(parsed?["schemaVersion"] as? Int == ProjectsPersistencePayload.currentVersion)
        let projectsArray = parsed?["projects"] as? [[String: Any]]
        #expect(projectsArray?.first?["name"] as? String == "Repo")
    }
}
