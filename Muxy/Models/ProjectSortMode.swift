import Foundation

enum ProjectSortMode: String, CaseIterable, Identifiable {
    case manual
    case active

    static let storageKey = "muxy.projectSortMode"
    static let defaultValue: ProjectSortMode = .manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .active: "Recently Active"
        }
    }
}
