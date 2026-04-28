import Foundation
import MuxyShared
import os

private let logger = Logger(subsystem: "app.muxy", category: "WorktreeSetupRunner")

@MainActor
enum WorktreeSetupRunner {
    static func run(sourceProjectPath: String, paneID: UUID) async {
        guard let commands = commandLine(sourceProjectPath: sourceProjectPath) else { return }

        for _ in 0 ..< 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let view = TerminalViewRegistry.shared.view(for: paneID), view.hasLiveSurface {
                view.sendText(commands)
                view.sendReturnKey()
                return
            }
        }
        logger.error("Timed out waiting for pane \(paneID.uuidString) before sending setup commands")
    }

    nonisolated static func commandLine(sourceProjectPath: String) -> String? {
        guard let config = RoostConfigLoader.load(fromProjectPath: sourceProjectPath) else { return nil }
        let commands = setupEntries(config: config).map { command in
            commandLine(command: command, globalEnv: config.env, globalKeychainEnv: config.keychainEnv)
        }
        guard !commands.isEmpty else { return nil }
        return commands.joined(separator: " && ")
    }

    nonisolated static func setupCommands(config: RoostConfig) -> [String] {
        setupEntries(config: config).map(\.command)
    }

    nonisolated static func setupEntries(config: RoostConfig) -> [RoostConfigSetupCommand] {
        config.setup
            .map {
                RoostConfigSetupCommand(
                    command: $0.command.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: $0.name,
                    env: $0.env,
                    keychainEnv: $0.keychainEnv
                )
            }
            .filter { !$0.command.isEmpty }
    }

    nonisolated static func commandLine(
        command: RoostConfigSetupCommand,
        globalEnv: [String: String],
        globalKeychainEnv: [String: RoostConfigKeychainEnv] = [:],
        keychainReader: RoostConfigEnvResolver.KeychainReader = AIUsageTokenReader.fromKeychain
    ) -> String {
        let globalResolved = RoostConfigEnvResolver.resolve(
            plain: globalEnv,
            keychain: globalKeychainEnv,
            keychainReader: keychainReader
        )
        let commandResolved = RoostConfigEnvResolver.resolve(
            plain: command.env,
            keychain: command.keychainEnv,
            keychainReader: keychainReader
        )
        let env = globalResolved.merging(commandResolved) { _, commandValue in commandValue }
        guard !env.isEmpty else { return command.command.trimmingCharacters(in: .whitespacesAndNewlines) }
        let prefix = env
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(ShellEscaper.escape($0.value))" }
            .joined(separator: " ")
        return "\(prefix) \(command.command.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}
