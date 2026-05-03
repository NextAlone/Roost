import Foundation
import MuxyShared

public struct HostdCreateSessionRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public let projectID: UUID
    public let worktreeID: UUID
    public let workspacePath: String
    public let agentKind: AgentKind
    public let command: String?
    public let createdAt: Date

    public init(
        id: UUID,
        projectID: UUID,
        worktreeID: UUID,
        workspacePath: String,
        agentKind: AgentKind,
        command: String?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.worktreeID = worktreeID
        self.workspacePath = workspacePath
        self.agentKind = agentKind
        self.command = command
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case projectID
        case worktreeID
        case workspacePath
        case agentKind
        case command
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectID = try container.decode(UUID.self, forKey: .projectID)
        worktreeID = try container.decode(UUID.self, forKey: .worktreeID)
        workspacePath = try container.decode(String.self, forKey: .workspacePath)
        agentKind = try container.decode(AgentKind.self, forKey: .agentKind)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

public struct HostdSessionIDRequest: Sendable, Codable, Equatable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public struct HostdAttachSessionResponse: Sendable, Codable, Equatable {
    public let record: SessionRecord
    public let ownership: HostdRuntimeOwnership

    public init(record: SessionRecord, ownership: HostdRuntimeOwnership) {
        self.record = record
        self.ownership = ownership
    }
}

public struct HostdReadSessionOutputRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public let timeout: TimeInterval

    public init(id: UUID, timeout: TimeInterval = 0) {
        self.id = id
        self.timeout = timeout
    }
}

public struct HostdReadSessionOutputResponse: Sendable, Codable, Equatable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }
}

public struct HostdWriteSessionInputRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public let data: Data

    public init(id: UUID, data: Data) {
        self.id = id
        self.data = data
    }
}

public enum HostdSessionSignal: String, Sendable, Codable, Equatable {
    case interrupt
}

public struct HostdSendSessionSignalRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public let signal: HostdSessionSignal

    public init(id: UUID, signal: HostdSessionSignal) {
        self.id = id
        self.signal = signal
    }
}

public struct HostdResizeSessionRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public let columns: UInt16
    public let rows: UInt16

    public init(id: UUID, columns: UInt16, rows: UInt16) {
        self.id = id
        self.columns = columns
        self.rows = rows
    }
}

public struct HostdXPCReply: Sendable, Codable, Equatable {
    public let ok: Bool
    public let data: Data?
    public let error: String?

    public init(ok: Bool, data: Data?, error: String?) {
        self.ok = ok
        self.data = data
        self.error = error
    }
}

public enum HostdXPCError: Error, Equatable, LocalizedError, Sendable {
    case errorReply(String)
    case missingPayload

    public var errorDescription: String? {
        switch self {
        case let .errorReply(message):
            message
        case .missingPayload:
            "Hostd XPC reply did not include a payload"
        }
    }
}

public enum HostdXPCCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode(_ value: some Encodable) throws -> Data {
        try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }

    public static func success() throws -> Data {
        try encode(HostdXPCReply(ok: true, data: nil, error: nil))
    }

    public static func success(_ value: some Encodable) throws -> Data {
        let payload = try encode(value)
        return try encode(HostdXPCReply(ok: true, data: payload, error: nil))
    }

    public static func failure(_ message: String) -> Data {
        let reply = HostdXPCReply(ok: false, data: nil, error: message)
        return (try? encode(reply)) ?? Data()
    }

    public static func decodeEmptyReply(from data: Data) throws {
        let reply = try decode(HostdXPCReply.self, from: data)
        guard reply.ok else { throw HostdXPCError.errorReply(reply.error ?? "Hostd XPC request failed") }
    }

    public static func decodeReply<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let reply = try decode(HostdXPCReply.self, from: data)
        guard reply.ok else { throw HostdXPCError.errorReply(reply.error ?? "Hostd XPC request failed") }
        guard let payload = reply.data else { throw HostdXPCError.missingPayload }
        return try decode(type, from: payload)
    }
}
