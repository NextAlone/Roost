import Darwin
import Dispatch
import Foundation
import os
import RoostHostdCore

private let logger = Logger(subsystem: "app.roost.hostd", category: "Daemon")

let socketPath = {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--socket"),
          arguments.indices.contains(index + 1)
    else { return HostdDaemonSocket.defaultSocketPath }
    return arguments[index + 1]
}()

signal(SIGPIPE, SIG_IGN)

func fail(_ message: String) -> Never {
    logger.error("\(message, privacy: .public)")
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let instanceLock: HostdDaemonInstanceLock
do {
    instanceLock = try HostdDaemonInstanceLock()
} catch {
    fail("hostd daemon failed to acquire instance lock: \(error.localizedDescription)")
}

let registry: HostdProcessRegistry
do {
    registry = try await HostdProcessRegistry(databaseURL: HostdStorage.defaultDatabaseURL())
} catch {
    fail("hostd daemon failed to open registry database: \(error.localizedDescription)")
}

do {
    try await registry.recoverRunningSessions()
} catch {
    logger.warning("hostd daemon failed to recover running sessions: \(error.localizedDescription, privacy: .public)")
}

let server = HostdDaemonSocketServer(socketPath: socketPath, registry: registry)
server.start()
while true {
    _ = instanceLock
    try await Task.sleep(for: .seconds(3600))
}
