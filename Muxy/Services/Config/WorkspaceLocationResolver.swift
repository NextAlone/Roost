import Foundation
import MuxyShared

enum WorkspaceLocationResolver {
    static func directory(projectID: UUID, projectPath: String, name: String) -> URL {
        let config = RoostConfigLoader.load(fromProjectPath: projectPath)
        return directory(projectID: projectID, projectPath: projectPath, name: name, config: config)
    }

    static func directory(projectID: UUID, projectPath: String, name: String, config: RoostConfig?) -> URL {
        guard let raw = config?.defaultWorkspaceLocation?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return MuxyFileStorage.worktreeDirectory(forProjectID: projectID, name: name)
        }

        let base = resolveBase(raw, projectPath: projectPath)
        return base.appendingPathComponent(name, isDirectory: true)
    }

    private static func resolveBase(_ raw: String, projectPath: String) -> URL {
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent(raw, isDirectory: true)
    }
}
