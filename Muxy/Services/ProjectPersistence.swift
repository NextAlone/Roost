import Foundation

protocol ProjectPersisting {
    func loadProjects() throws -> [Project]
    func saveProjects(_ projects: [Project]) throws
}

struct ProjectsPersistencePayload {
    static let currentVersion: Int = 2

    let schemaVersion: Int
    let projects: [Project]

    static func decode(_ data: Data) throws -> ProjectsPersistencePayload {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(EnvelopeForm.self, from: data) {
            return ProjectsPersistencePayload(
                schemaVersion: envelope.schemaVersion,
                projects: envelope.projects
            )
        }
        let bare = try decoder.decode([Project].self, from: data)
        return ProjectsPersistencePayload(schemaVersion: 1, projects: bare)
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(EnvelopeForm(schemaVersion: schemaVersion, projects: projects))
    }

    private struct EnvelopeForm: Codable {
        let schemaVersion: Int
        let projects: [Project]
    }
}

final class FileProjectPersistence: ProjectPersisting {
    private let fileURL: URL

    init(fileURL: URL = MuxyFileStorage.fileURL(filename: "projects.json")) {
        self.fileURL = fileURL
    }

    func loadProjects() throws -> [Project] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try ProjectsPersistencePayload.decode(data).projects
    }

    func saveProjects(_ projects: [Project]) throws {
        let payload = ProjectsPersistencePayload(
            schemaVersion: ProjectsPersistencePayload.currentVersion,
            projects: projects
        )
        let data = try payload.encode()
        try data.write(to: fileURL, options: .atomic)
    }
}
