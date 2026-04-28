import Foundation

public struct RoostConfig: Sendable, Codable {
    public let schemaVersion: Int
    public let env: [String: String]
    public let keychainEnv: [String: RoostConfigKeychainEnv]
    public let defaultWorkspaceLocation: String?
    public let setup: [RoostConfigSetupCommand]
    public let teardown: [RoostConfigSetupCommand]
    public let agentPresets: [RoostConfigAgentPreset]
    public let notifications: RoostConfigNotifications?

    public init(
        schemaVersion: Int = 1,
        env: [String: String] = [:],
        keychainEnv: [String: RoostConfigKeychainEnv] = [:],
        defaultWorkspaceLocation: String? = nil,
        setup: [RoostConfigSetupCommand] = [],
        teardown: [RoostConfigSetupCommand] = [],
        agentPresets: [RoostConfigAgentPreset] = [],
        notifications: RoostConfigNotifications? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.env = env
        self.keychainEnv = keychainEnv
        self.defaultWorkspaceLocation = defaultWorkspaceLocation
        self.setup = setup
        self.teardown = teardown
        self.agentPresets = agentPresets
        self.notifications = notifications
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case env
        case defaultWorkspaceLocation
        case setup
        case teardown
        case agentPresets
        case notifications
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        let decodedEnv = RoostConfigEnv.decode(container, forKey: .env)
        env = decodedEnv.plain
        keychainEnv = decodedEnv.keychain
        defaultWorkspaceLocation = try container.decodeIfPresent(String.self, forKey: .defaultWorkspaceLocation)
        setup = (try? container.decodeIfPresent([RoostConfigSetupCommand].self, forKey: .setup)) ?? []
        teardown = (try? container.decodeIfPresent([RoostConfigSetupCommand].self, forKey: .teardown)) ?? []

        let rawArray = (try? container.decodeIfPresent([RoostConfigAgentPresetTolerant].self, forKey: .agentPresets)) ?? []
        agentPresets = rawArray.compactMap(\.preset)
        notifications = try container.decodeIfPresent(RoostConfigNotifications.self, forKey: .notifications)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(EncodedEnv(plain: env, keychain: keychainEnv), forKey: .env)
        try container.encodeIfPresent(defaultWorkspaceLocation, forKey: .defaultWorkspaceLocation)
        try container.encode(setup, forKey: .setup)
        try container.encode(teardown, forKey: .teardown)
        try container.encode(agentPresets, forKey: .agentPresets)
        try container.encodeIfPresent(notifications, forKey: .notifications)
    }
}

public struct RoostConfigNotifications: Sendable, Codable, Hashable {
    public let enabled: Bool?
    public let toastEnabled: Bool?
    public let sound: String?
    public let toastPosition: String?

    public init(
        enabled: Bool? = nil,
        toastEnabled: Bool? = nil,
        sound: String? = nil,
        toastPosition: String? = nil
    ) {
        self.enabled = enabled
        self.toastEnabled = toastEnabled
        self.sound = sound
        self.toastPosition = toastPosition
    }
}

public struct RoostConfigKeychainEnv: Sendable, Codable, Hashable {
    public let service: String
    public let account: String?

    public init(service: String, account: String? = nil) {
        self.service = service
        self.account = account
    }
}

public struct RoostConfigSetupCommand: Sendable, Codable, Hashable {
    public let command: String
    public let name: String?
    public let cwd: String?
    public let env: [String: String]
    public let keychainEnv: [String: RoostConfigKeychainEnv]

    public init(
        command: String,
        name: String? = nil,
        cwd: String? = nil,
        env: [String: String] = [:],
        keychainEnv: [String: RoostConfigKeychainEnv] = [:]
    ) {
        self.command = command
        self.name = name
        self.cwd = cwd
        self.env = env
        self.keychainEnv = keychainEnv
    }

    private enum CodingKeys: String, CodingKey {
        case command
        case name
        case cwd
        case env
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        let decodedEnv = RoostConfigEnv.decode(container, forKey: .env)
        env = decodedEnv.plain
        keychainEnv = decodedEnv.keychain
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encode(EncodedEnv(plain: env, keychain: keychainEnv), forKey: .env)
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
    public let keychainEnv: [String: RoostConfigKeychainEnv]
    public let cardinality: RoostConfigCardinality

    public init(
        name: String,
        kind: AgentKind,
        command: String?,
        env: [String: String] = [:],
        keychainEnv: [String: RoostConfigKeychainEnv] = [:],
        cardinality: RoostConfigCardinality = .shared
    ) {
        self.name = name
        self.kind = kind
        self.command = command
        self.env = env
        self.keychainEnv = keychainEnv
        self.cardinality = cardinality
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case kind
        case command
        case env
        case cardinality
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(AgentKind.self, forKey: .kind)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        let decodedEnv = RoostConfigEnv.decode(container, forKey: .env)
        env = decodedEnv.plain
        keychainEnv = decodedEnv.keychain
        cardinality = (try? container.decodeIfPresent(RoostConfigCardinality.self, forKey: .cardinality)) ?? .shared
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encode(EncodedEnv(plain: env, keychain: keychainEnv), forKey: .env)
        try container.encode(cardinality, forKey: .cardinality)
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
        let decodedEnv = RoostConfigEnv.decode(container, forKey: .env)
        let cardinality = (try? container.decodeIfPresent(RoostConfigCardinality.self, forKey: .cardinality)) ?? .shared
        preset = RoostConfigAgentPreset(
            name: name,
            kind: kind,
            command: command,
            env: decodedEnv.plain,
            keychainEnv: decodedEnv.keychain,
            cardinality: cardinality
        )
    }
}

private enum RoostConfigEnv {
    static func decode<Key: CodingKey>(
        _ container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> (plain: [String: String], keychain: [String: RoostConfigKeychainEnv]) {
        guard let raw = try? container.decodeIfPresent(RawEnv.self, forKey: key) else { return ([:], [:]) }
        let plain = raw.values.filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let keychain = raw.keychainValues.filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return (plain, keychain)
    }
}

private struct RawEnv: Decodable {
    let values: [String: String]
    let keychainValues: [String: RoostConfigKeychainEnv]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var decoded: [String: String] = [:]
        var keychainDecoded: [String: RoostConfigKeychainEnv] = [:]
        for key in container.allKeys {
            guard let value = try? container.decode(RawEnvValue.self, forKey: key) else { continue }
            if let plain = value.plain {
                decoded[key.stringValue] = plain
            } else if let keychain = value.keychain {
                keychainDecoded[key.stringValue] = keychain
            }
        }
        values = decoded
        keychainValues = keychainDecoded
    }
}

private struct RawEnvValue: Decodable {
    let plain: String?
    let keychain: RoostConfigKeychainEnv?

    private enum CodingKeys: String, CodingKey {
        case fromKeychain
        case account
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            plain = value
            keychain = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let service = try container.decodeIfPresent(String.self, forKey: .fromKeychain)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !service.isEmpty
        {
            let account = try container.decodeIfPresent(String.self, forKey: .account)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            plain = nil
            keychain = RoostConfigKeychainEnv(service: service, account: account?.isEmpty == true ? nil : account)
        } else {
            plain = nil
            keychain = nil
        }
    }
}

private struct EncodedEnv: Encodable {
    let plain: [String: String]
    let keychain: [String: RoostConfigKeychainEnv]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in plain where !keychain.keys.contains(key) {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            try container.encode(value, forKey: codingKey)
        }
        for (key, value) in keychain {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            try container.encode(EncodedKeychainEnv(value: value), forKey: codingKey)
        }
    }
}

private struct EncodedKeychainEnv: Encodable {
    let value: RoostConfigKeychainEnv

    private enum CodingKeys: String, CodingKey {
        case fromKeychain
        case account
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.service, forKey: .fromKeychain)
        try container.encodeIfPresent(value.account, forKey: .account)
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
