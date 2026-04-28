import Foundation
import MuxyShared
import os

private let teardownLogger = Logger(subsystem: "app.muxy", category: "WorktreeTeardownRunner")

enum WorktreeTeardownRunner {
    static func run(sourceProjectPath: String, worktreePath: String) async {
        guard let config = RoostConfigLoader.load(fromProjectPath: sourceProjectPath) else { return }
        let commands = teardownEntries(config: config)
        guard !commands.isEmpty else { return }

        for command in commands {
            do {
                try await run(command: command, globalConfig: config, worktreePath: worktreePath)
            } catch {
                teardownLogger.error("Failed to run teardown command for \(worktreePath): \(error.localizedDescription)")
            }
        }
    }

    static func teardownCommands(config: RoostConfig) -> [String] {
        teardownEntries(config: config).map(\.command)
    }

    static func teardownEntries(config: RoostConfig) -> [RoostConfigSetupCommand] {
        config.teardown
            .map {
                RoostConfigSetupCommand(
                    command: $0.command.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: $0.name,
                    cwd: $0.cwd,
                    env: $0.env,
                    keychainEnv: $0.keychainEnv
                )
            }
            .filter { !$0.command.isEmpty }
    }

    static func resolvedWorkingDirectory(command: RoostConfigSetupCommand, worktreePath: String) -> URL {
        guard let raw = command.cwd?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return URL(fileURLWithPath: worktreePath, isDirectory: true)
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return URL(fileURLWithPath: worktreePath, isDirectory: true)
            .appendingPathComponent(raw, isDirectory: true)
    }

    static func resolvedEnvironment(
        command: RoostConfigSetupCommand,
        globalConfig: RoostConfig,
        inherited: [String: String] = ProcessInfo.processInfo.environment,
        keychainReader: RoostConfigEnvResolver.KeychainReader = AIUsageTokenReader.fromKeychain
    ) -> [String: String] {
        let globalResolved = RoostConfigEnvResolver.resolve(
            plain: globalConfig.env,
            keychain: globalConfig.keychainEnv,
            keychainReader: keychainReader
        )
        let commandResolved = RoostConfigEnvResolver.resolve(
            plain: command.env,
            keychain: command.keychainEnv,
            keychainReader: keychainReader
        )
        return inherited
            .merging(globalResolved) { _, configValue in configValue }
            .merging(commandResolved) { _, commandValue in commandValue }
    }

    private static func run(
        command: RoostConfigSetupCommand,
        globalConfig: RoostConfig,
        worktreePath: String
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command.command]
        process.currentDirectoryURL = resolvedWorkingDirectory(command: command, worktreePath: worktreePath)
        process.environment = resolvedEnvironment(command: command, globalConfig: globalConfig)
        let output = FileHandle(forWritingAtPath: "/dev/null")
        let error = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = output
        process.standardError = error
        defer {
            try? output?.close()
            try? error?.close()
        }

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw TeardownError.failed(status: process.terminationStatus)
        }
    }

    enum TeardownError: Error {
        case failed(status: Int32)
    }
}
