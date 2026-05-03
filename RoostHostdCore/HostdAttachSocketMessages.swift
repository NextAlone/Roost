import Darwin
import Foundation

public enum HostdAttachSocketOperation: String, Sendable, Codable, Equatable {
    case runtimeIdentity
    case runtimeOwnership
    case createSession
    case markExited
    case listLiveSessions
    case listAllSessions
    case deleteSession
    case pruneExited
    case markAllRunningExited
    case attachSession
    case releaseSession
    case terminateSession
    case readSessionOutput
    case readSessionOutputStream
    case writeSessionInput
    case resizeSession
    case sendSessionSignal
}

public struct HostdAttachSocketRequest: Sendable, Codable, Equatable {
    public let operation: HostdAttachSocketOperation
    public let payload: Data

    public init(operation: HostdAttachSocketOperation, payload: Data) {
        self.operation = operation
        self.payload = payload
    }
}

public struct HostdAttachSocketResponse: Sendable, Codable, Equatable {
    public let payload: Data

    public init(payload: Data) {
        self.payload = payload
    }
}

public struct HostdDaemonRuntimeIdentity: Sendable, Codable, Equatable {
    public static let currentProtocolVersion = 6

    public let protocolVersion: Int

    public init(protocolVersion: Int = Self.currentProtocolVersion) {
        self.protocolVersion = protocolVersion
    }

    public var isCompatible: Bool {
        protocolVersion == Self.currentProtocolVersion
    }
}

public enum HostdDaemonSocket {
    public static var defaultSocketPath: String {
        "/tmp/roost-hostd-daemon-\(getuid()).sock"
    }
}
