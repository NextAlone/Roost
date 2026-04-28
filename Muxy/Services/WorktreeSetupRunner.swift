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
        let commands = setupCommands(config: config)
        guard !commands.isEmpty else { return nil }
        return commands.joined(separator: " && ")
    }

    nonisolated static func setupCommands(config: RoostConfig) -> [String] {
        config.setup
            .map(\.command)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
