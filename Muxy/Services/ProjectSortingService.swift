import Foundation

enum ProjectSortingService {
    static let activeThreshold: TimeInterval = 60 * 60 * 4

    static func sort(
        projects: [Project],
        worktreesByProject: [UUID: [Worktree]],
        mode: ProjectSortMode,
        now: Date
    ) -> [Project] {
        guard mode == .active else {
            return projects.sorted { $0.sortOrder < $1.sortOrder }
        }
        let boundary = now.addingTimeInterval(-activeThreshold)
        let stamped: [(Project, Date?)] = projects.map {
            ($0, lastActiveAt(for: $0, worktreesByProject: worktreesByProject))
        }
        let recent = stamped
            .filter { ($0.1 ?? .distantPast) >= boundary }
            .sorted { ($0.1 ?? .distantPast) > ($1.1 ?? .distantPast) }
            .map(\.0)
        let rest = stamped
            .filter { ($0.1 ?? .distantPast) < boundary }
            .map(\.0)
            .sorted { $0.sortOrder < $1.sortOrder }
        return recent + rest
    }

    private static func lastActiveAt(
        for project: Project,
        worktreesByProject: [UUID: [Worktree]]
    ) -> Date? {
        worktreesByProject[project.id]?.compactMap(\.lastActiveAt).max()
    }
}
