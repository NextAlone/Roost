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
}
