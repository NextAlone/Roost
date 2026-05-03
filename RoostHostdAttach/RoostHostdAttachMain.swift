import Darwin
import Foundation
import RoostHostdCore

enum HostdAttachError: Error, LocalizedError {
    case missingSession
    case invalidSession(String)
    case proxyUnavailable
    case socketFailed(String)
    case unexpectedRuntime(HostdRuntimeOwnership)

    var errorDescription: String? {
        switch self {
        case .missingSession:
            "Missing required --session argument"
        case let .invalidSession(value):
            "Invalid session id: \(value)"
        case .proxyUnavailable:
            "Roost hostd XPC proxy is unavailable"
        case let .socketFailed(message):
            "Roost hostd attach socket failed: \(message)"
        case let .unexpectedRuntime(ownership):
            "Hostd session has unexpected runtime ownership: \(ownership.rawValue)"
        }
    }
}

protocol HostdAttachOutputReading: Sendable {
    func readSessionOutputStream(
        id: UUID,
        after sequence: UInt64?,
        timeout: TimeInterval,
        limit: Int?,
        mode: HostdOutputStreamReadMode
    ) async throws -> HostdOutputRead
}

extension HostdAttachClient: HostdAttachOutputReading {}

private let hostdAttachSynchronizedOutputReset = Data("\u{1B}[?2026l".utf8)

extension HostdOutputRead {
    var terminalOutputData: Data {
        var data = chunks.reduce(into: Data()) { result, chunk in
            result.append(chunk.data)
        }
        if !data.isEmpty {
            data.append(hostdAttachSynchronizedOutputReset)
        }
        return data
    }
}

struct HostdAttachOutputReplay {
    private let sessionID: UUID
    private let client: any HostdAttachOutputReading
    private var sequence: UInt64?

    init(sessionID: UUID, client: any HostdAttachOutputReading) {
        self.sessionID = sessionID
        self.client = client
    }

    mutating func readNext() async throws -> HostdOutputRead {
        let output = try await client.readSessionOutputStream(
            id: sessionID,
            after: sequence,
            timeout: 0.25,
            limit: nil,
            mode: sequence == nil ? .terminalSnapshot : .raw
        )
        sequence = output.nextSequence
        return output
    }
}

struct HostdAttachArguments {
    let sessionID: UUID
    let serviceName: String
    let socketPath: String?

    static func parse(_ arguments: [String]) throws -> HostdAttachArguments {
        var sessionValue: String?
        var serviceName = "app.roost.mac.hostd"
        var socketPath: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--session":
                index += 1
                guard index < arguments.count else { throw HostdAttachError.missingSession }
                sessionValue = arguments[index]
            case "--service-name":
                index += 1
                guard index < arguments.count else { throw HostdAttachError.proxyUnavailable }
                serviceName = arguments[index]
            case "--socket":
                index += 1
                guard index < arguments.count else { throw HostdAttachError.socketFailed("missing socket path") }
                socketPath = arguments[index]
            default:
                break
            }
            index += 1
        }
        guard let sessionValue else { throw HostdAttachError.missingSession }
        guard let sessionID = UUID(uuidString: sessionValue) else {
            throw HostdAttachError.invalidSession(sessionValue)
        }
        return HostdAttachArguments(sessionID: sessionID, serviceName: serviceName, socketPath: socketPath)
    }
}

@main
enum RoostHostdAttachMain {
    static func main() async {
        do {
            try await run()
        } catch {
            let message = "\(error.localizedDescription)\n"
            try? HostdAttachTerminal.writeAll(Data(message.utf8), to: STDERR_FILENO)
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let arguments = try HostdAttachArguments.parse(Array(CommandLine.arguments.dropFirst()))
        let client = HostdAttachClient(serviceName: arguments.serviceName, socketPath: arguments.socketPath)
        var terminal = HostdAttachTerminal.standard()
        try terminal.enableRawMode()
        defer {
            terminal.restore()
        }

        let response = try await client.attachSession(id: arguments.sessionID)
        guard response.ownership == .hostdOwnedProcess else {
            throw HostdAttachError.unexpectedRuntime(response.ownership)
        }

        if let size = terminal.size() {
            try? await client.resizeSession(id: arguments.sessionID, columns: size.columns, rows: size.rows)
        }

        let resizeSource = HostdAttachResizeSource(
            sessionID: arguments.sessionID,
            client: client,
            terminal: terminal
        )
        resizeSource.start()
        defer {
            resizeSource.cancel()
        }

        let inputTask = Task.detached {
            try await forwardInput(sessionID: arguments.sessionID, client: client)
        }
        defer {
            inputTask.cancel()
        }

        do {
            try await forwardOutput(sessionID: arguments.sessionID, client: client)
            try? await client.releaseSession(id: arguments.sessionID)
        } catch {
            try? await client.releaseSession(id: arguments.sessionID)
            throw error
        }
    }

    private static func forwardInput(sessionID: UUID, client: HostdAttachClient) async throws {
        while !Task.isCancelled {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                read(STDIN_FILENO, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count > 0 {
                try await client.writeSessionInput(id: sessionID, data: Data(buffer.prefix(count)))
                continue
            }
            if count == 0 { return }
            if errno == EINTR { continue }
            throw HostdAttachTerminalError.rawModeFailed(errnoMessage())
        }
    }

    private static func forwardOutput(sessionID: UUID, client: HostdAttachClient) async throws {
        var replay = HostdAttachOutputReplay(sessionID: sessionID, client: client)
        while !Task.isCancelled {
            let output = try await replay.readNext()
            try HostdAttachTerminal.writeAll(output.terminalOutputData)
            if output.streamEnded { return }
        }
    }
}

final class HostdAttachResizeSource {
    private let sessionID: UUID
    private let client: HostdAttachClient
    private let terminal: HostdAttachTerminal
    private let source: DispatchSourceSignal

    init(sessionID: UUID, client: HostdAttachClient, terminal: HostdAttachTerminal) {
        self.sessionID = sessionID
        self.client = client
        self.terminal = terminal
        self.source = DispatchSource.makeSignalSource(signal: SIGWINCH)
    }

    func start() {
        signal(SIGWINCH, SIG_IGN)
        source.setEventHandler { [sessionID, client, terminal] in
            guard let size = terminal.size() else { return }
            Task {
                try? await client.resizeSession(id: sessionID, columns: size.columns, rows: size.rows)
            }
        }
        source.resume()
    }

    func cancel() {
        source.cancel()
    }
}
