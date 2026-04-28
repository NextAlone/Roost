import Foundation

public struct RoostConfig: Sendable, Codable {
    public let schemaVersion: Int
    public let env: [String: String]
    public let defaultWorkspaceLocation: String?
    public let setup: [RoostConfigSetupCommand]
    public let agentPresets: [RoostConfigAgentPreset]

    public init(
        schemaVersion: Int = 1,
        env: [String: String] = [:],
        defaultWorkspaceLocation: String? = nil,
        setup: [RoostConfigSetupCommand] = [],
        agentPresets: [RoostConfigAgentPreset] = []
    ) {
        self.schemaVersion = schemaVersion
        self.env = env
        self.defaultWorkspaceLocation = defaultWorkspaceLocation
        self.setup = setup
        self.agentPresets = agentPresets
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case env
        case defaultWorkspaceLocation
        case setup
        case agentPresets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        env = RoostConfigEnv.decode(container, forKey: .env)
        defaultWorkspaceLocation = try container.decodeIfPresent(String.self, forKey: .defaultWorkspaceLocation)
        setup = (try? container.decodeIfPresent([RoostConfigSetupCommand].self, forKey: .setup)) ?? []

        let rawArray = (try? container.decodeIfPresent([RoostConfigAgentPresetTolerant].self, forKey: .agentPresets)) ?? []
        agentPresets = rawArray.compactMap(\.preset)
    }
}

public struct RoostConfigSetupCommand: Sendable, Codable, Hashable {
    public let command: String
    public let name: String?
    public let env: [String: String]

    public init(command: String, name: String? = nil, env: [String: String] = [:]) {
        self.command = command
        self.name = name
        self.env = env
    }

    private enum CodingKeys: String, CodingKey {
        case command
        case name
        case env
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        env = RoostConfigEnv.decode(container, forKey: .env)
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
    public let env: [String: String]
    public let cardinality: RoostConfigCardinality

    public init(
        name: String,
        kind: AgentKind,
        command: String?,
        env: [String: String] = [:],
        cardinality: RoostConfigCardinality = .shared
    ) {
        self.name = name
        self.kind = kind
        self.command = command
        self.env = env
        self.cardinality = cardinality
    }
}

private struct RoostConfigAgentPresetTolerant: Decodable {
    let preset: RoostConfigAgentPreset?

    private enum CodingKeys: String, CodingKey {
        case name
        case kind
        case command
        case env
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
        let env = RoostConfigEnv.decode(container, forKey: .env)
        let cardinality = (try? container.decodeIfPresent(RoostConfigCardinality.self, forKey: .cardinality)) ?? .shared
        preset = RoostConfigAgentPreset(name: name, kind: kind, command: command, env: env, cardinality: cardinality)
    }
}

private enum RoostConfigEnv {
    static func decode<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, forKey key: Key) -> [String: String] {
        guard let raw = try? container.decodeIfPresent(RawEnv.self, forKey: key) else { return [:] }
        return raw.values.filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

private struct RawEnv: Decodable {
    let values: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var decoded: [String: String] = [:]
        for key in container.allKeys {
            if let value = try? container.decode(String.self, forKey: key) {
                decoded[key.stringValue] = value
            }
        }
        values = decoded
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}
