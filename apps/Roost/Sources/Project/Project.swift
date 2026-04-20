import Foundation

/// Persisted, user-visible project: one jj repo on disk. Persistence moves
/// to SQLite in M8; today it's a JSON blob in UserDefaults so projects
/// survive app restarts.
struct Project: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var path: String
    /// True if `jj status` succeeded in this directory when it was added.
    /// Controls whether the launcher offers the "new jj workspace" toggle.
    var isJjRepo: Bool

    init(id: UUID = UUID(), name: String, path: String, isJjRepo: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.isJjRepo = isJjRepo
    }

    /// Default display name: the last path component (`/a/b/foo` → `foo`).
    static func suggestedName(for path: String) -> String {
        let last = (path as NSString).lastPathComponent
        return last.isEmpty ? path : last
    }

    /// Sentinel ID representing the "Scratch" (projectID = nil) sidebar row.
    /// SwiftUI's `List` selection binding doesn't handle `.tag(Optional.none)`
    /// reliably; use a stable UUID and translate at the boundary.
    static let scratchID: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [Project]

    private static let defaultsKey = "sh.roost.app.projects"

    init() {
        self.projects = Self.loadFromDefaults()
    }

    // MARK: Mutations

    func add(path: String, isJjRepo: Bool) -> Project {
        let project = Project(
            name: Project.suggestedName(for: path),
            path: path,
            isJjRepo: isJjRepo
        )
        projects.append(project)
        save()
        return project
    }

    func remove(_ id: Project.ID) {
        projects.removeAll { $0.id == id }
        save()
    }

    func rename(_ id: Project.ID, to name: String) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].name = name
        save()
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func loadFromDefaults() -> [Project] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Project].self, from: data)
        else { return [] }
        return decoded
    }
}
