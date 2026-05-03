import Foundation
import RoostHostdCore

enum HostdDaemonLauncher {
    static var defaultSocketPath: String {
        HostdDaemonSocket.defaultSocketPath
    }

    static func makeClient(
        socketPath: String = defaultSocketPath,
        executablePath: String? = defaultExecutablePath()
    ) async throws -> any RoostHostdClient {
        try await ensureRunning(socketPath: socketPath, executablePath: executablePath)
        return XPCHostdClient(transport: HostdSocketTransport(socketPath: socketPath))
    }

    static func ensureRunning(socketPath: String = defaultSocketPath, executablePath: String? = defaultExecutablePath()) async throws {
        if await canConnect(socketPath: socketPath) { return }
        guard let executablePath else {
            throw HostdDaemonLauncherError.executableMissing
        }
        try launch(executablePath: executablePath, socketPath: socketPath)
        for _ in 0 ..< 80 {
            if await canConnect(socketPath: socketPath) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw HostdDaemonLauncherError.startTimedOut
    }

    private static func launch(executablePath: String, socketPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--socket", socketPath]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "ROOST_HOSTD_RUNTIME": "hostd-owned-process",
        ]) { _, new in new }
        let null = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = null
        process.standardError = null
        try process.run()
    }

    private static func canConnect(socketPath: String) async -> Bool {
        let transport = HostdSocketTransport(socketPath: socketPath)
        let identity: HostdDaemonRuntimeIdentity
        do {
            identity = try await HostdAsyncTimeout.run(seconds: 0.5, operation: "hostd daemon identity") {
                try await transport.runtimeIdentity()
            }
        } catch {
            return false
        }
        return identity.isCompatible
    }

    private static func defaultExecutablePath() -> String? {
        let bundleURL = Bundle.main.bundleURL
        let appPath = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent("roost-hostd-daemon")
            .path(percentEncoded: false)
        if FileManager.default.isExecutableFile(atPath: appPath) {
            return appPath
        }

        let localPath = bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("roost-hostd-daemon")
            .path(percentEncoded: false)
        if FileManager.default.isExecutableFile(atPath: localPath) {
            return localPath
        }
        return nil
    }
}

enum HostdDaemonLauncherError: Error, LocalizedError, Equatable {
    case executableMissing
    case startTimedOut

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            "roost-hostd-daemon helper not found"
        case .startTimedOut:
            "roost-hostd-daemon did not start"
        }
    }
}
