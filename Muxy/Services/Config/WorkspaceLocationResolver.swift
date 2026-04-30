import Foundation
import MuxyShared

enum WorkspaceLocationResolver {
    static func directory(projectID: UUID, projectPath: String, name: String) -> URL {
        let config = try? RoostAppConfigStore.load()
        return directory(projectID: projectID, projectPath: projectPath, name: name, appConfig: config)
    }

    static func directory(projectID: UUID, projectPath _: String, name: String, appConfig: RoostConfig?) -> URL {
        guard let raw = appConfig?.defaultWorkspaceLocation?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return MuxyFileStorage.worktreeDirectory(forProjectID: projectID, name: name)
        }

        let base = resolveBase(raw)
        return base.appendingPathComponent(name, isDirectory: true)
    }

    private static func resolveBase(_ raw: String) -> URL {
        if raw == "~" {
            return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
        if raw.hasPrefix("~/") {
            return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(String(raw.dropFirst(2)), isDirectory: true)
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(raw, isDirectory: true)
    }
}
