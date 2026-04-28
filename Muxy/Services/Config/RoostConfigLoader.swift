import Foundation
import MuxyShared

enum RoostConfigLoader {
    static func load(fromProjectPath projectPath: String) -> RoostConfig? {
        if let config = loadRoost(fromProjectPath: projectPath) {
            return config
        }
        return loadLegacy(fromProjectPath: projectPath)
    }

    private static func loadRoost(fromProjectPath projectPath: String) -> RoostConfig? {
        try? RoostConfigStore.load(projectPath: projectPath)
    }

    private static func loadLegacy(fromProjectPath projectPath: String) -> RoostConfig? {
        let url = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".muxy")
            .appendingPathComponent("worktree.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let legacy = try? JSONDecoder().decode(LegacyWorktreeConfig.self, from: data) else { return nil }
        return RoostConfig(
            schemaVersion: 1,
            env: [:],
            defaultWorkspaceLocation: nil,
            setup: legacy.setup.map { RoostConfigSetupCommand(command: $0.command, name: $0.name) },
            teardown: [],
            agentPresets: [],
            notifications: nil
        )
    }
}

private struct LegacyWorktreeConfig: Decodable {
    struct Entry: Decodable {
        let command: String
        let name: String?
    }

    let setup: [Entry]

    private enum CodingKeys: String, CodingKey {
        case setup
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let entries = try? container.decode([Entry].self, forKey: .setup) {
            setup = entries
        } else if let strings = try? container.decode([String].self, forKey: .setup) {
            setup = strings.map { Entry(command: $0, name: nil) }
        } else {
            setup = []
        }
    }
}
