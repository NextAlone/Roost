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
        // Re-probe each project on startup: an older build saved projects
        // without the isJjRepo flag, and a dir's jj-ness can change between
        // launches (e.g. the user ran `jj init`). `jj status --quiet` is a
        // cheap process spawn (~tens of ms per project).
        refreshVcsFlags()
    }

    /// Re-run `jj status` against each project's path to keep isJjRepo
    /// honest.
    func refreshVcsFlags() {
        for idx in projects.indices {
            let wasJj = projects[idx].isJjRepo
            let nowJj = RoostBridge.isJjRepo(dir: projects[idx].path)
            NSLog("[Roost] refreshVcs name=%@ path=%@ was=%d now=%d",
                  projects[idx].name, projects[idx].path,
                  wasJj ? 1 : 0, nowJj ? 1 : 0)
            if wasJj != nowJj {
                projects[idx].isJjRepo = nowJj
            }
        }
        save()
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

    /// Move `srcID` to directly before `targetID` in the sidebar order.
    /// No-op if either ID is missing or they refer to the same row.
    func move(_ srcID: Project.ID, before targetID: Project.ID) {
        guard srcID != targetID,
              let src = projects.firstIndex(where: { $0.id == srcID }),
              let dst = projects.firstIndex(where: { $0.id == targetID })
        else { return }
        let p = projects.remove(at: src)
        // After removal, if we pulled from above the destination, `dst` slid
        // up by one — insert at dst-1 to preserve the "before target" intent.
        let adjusted = src < dst ? dst - 1 : dst
        projects.insert(p, at: adjusted)
        save()
    }

    // MARK: Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        // Hop off-main: UserDefaults.set can block under disk pressure and
        // we call this on every rename / reorder / VCS refresh, which used
        // to stall the sidebar during rapid interaction.
        DispatchQueue.global(qos: .utility).async {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func loadFromDefaults() -> [Project] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Project].self, from: data)
        else { return [] }
        return decoded
    }
}
