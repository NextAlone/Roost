import Foundation

public struct RoostConfig: Sendable, Codable {
    public let schemaVersion: Int
    public let setup: [RoostConfigSetupCommand]
    public let agentPresets: [RoostConfigAgentPreset]

    public init(
        schemaVersion: Int = 1,
        setup: [RoostConfigSetupCommand] = [],
        agentPresets: [RoostConfigAgentPreset] = []
    ) {
        self.schemaVersion = schemaVersion
        self.setup = setup
        self.agentPresets = agentPresets
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case setup
        case agentPresets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        setup = (try? container.decodeIfPresent([RoostConfigSetupCommand].self, forKey: .setup)) ?? []

        let rawArray = (try? container.decodeIfPresent([RoostConfigAgentPresetTolerant].self, forKey: .agentPresets)) ?? []
        agentPresets = rawArray.compactMap(\.preset)
    }
}

public struct RoostConfigSetupCommand: Sendable, Codable, Hashable {
    public let command: String
    public let name: String?

    public init(command: String, name: String? = nil) {
        self.command = command
        self.name = name
    }
}

public enum RoostConfigCardinality: String, Sendable, Codable {
    case shared
    case dedicated
}

public struct RoostConfigAgentPreset: Sendable, Codable, Hashable {
    public let name: String
    public let kind: AgentKind
    public let command: String?
    public let cardinality: RoostConfigCardinality

    public init(
        name: String,
        kind: AgentKind,
        command: String?,
        cardinality: RoostConfigCardinality = .shared
    ) {
        self.name = name
        self.kind = kind
        self.command = command
        self.cardinality = cardinality
    }
}

private struct RoostConfigAgentPresetTolerant: Decodable {
    let preset: RoostConfigAgentPreset?

    private enum CodingKeys: String, CodingKey {
        case name
        case kind
        case command
        case cardinality
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        guard let kindRaw = try container.decodeIfPresent(String.self, forKey: .kind),
              let kind = AgentKind(rawValue: kindRaw)
        else {
            preset = nil
            return
        }
        let command = try container.decodeIfPresent(String.self, forKey: .command)
        let cardinality = (try? container.decodeIfPresent(RoostConfigCardinality.self, forKey: .cardinality)) ?? .shared
        preset = RoostConfigAgentPreset(name: name, kind: kind, command: command, cardinality: cardinality)
    }
}
