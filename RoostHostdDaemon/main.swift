import Darwin
import Dispatch
import Foundation
import RoostHostdCore

let socketPath = {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: "--socket"),
          arguments.indices.contains(index + 1)
    else { return HostdDaemonSocket.defaultSocketPath }
    return arguments[index + 1]
}()

signal(SIGPIPE, SIG_IGN)

let instanceLock = try HostdDaemonInstanceLock()
let registry = try await HostdProcessRegistry(databaseURL: HostdStorage.defaultDatabaseURL())
let server = HostdDaemonSocketServer(socketPath: socketPath, registry: registry)
server.start()
while true {
    _ = instanceLock
    try await Task.sleep(for: .seconds(3600))
}
