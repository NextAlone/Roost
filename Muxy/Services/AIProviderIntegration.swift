import Foundation
import os

private let logger = Logger(subsystem: "app.muxy", category: "AIProviderRegistry")

protocol AIProviderIntegration {
    var id: String { get }
    var displayName: String { get }
    var socketTypeKey: String { get }
    var iconName: String { get }
    var executableNames: [String] { get }

    func isToolInstalled() -> Bool
}

extension AIProviderIntegration {
    var settingsKey: String { "muxy.notifications.provider.\(id).enabled" }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: settingsKey, fallback: true) }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: settingsKey) }
    }

    func isToolInstalled() -> Bool {
        let home = NSHomeDirectory()
        let searchPaths = executableNames.flatMap { name in
            [
                "\(home)/.local/bin/\(name)",
                "/usr/local/bin/\(name)",
                "/opt/homebrew/bin/\(name)",
            ]
        }
        return searchPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

@MainActor
final class AIProviderRegistry {
    static let shared = AIProviderRegistry()

    private let claudeCodeProvider = ClaudeCodeProvider()
    private let openCodeProvider = OpenCodeProvider()
    private let codexProvider = CodexProvider()
    private let cursorProvider = CursorProvider()

    lazy var providers: [AIProviderIntegration] = [
        claudeCodeProvider,
        openCodeProvider,
        codexProvider,
        cursorProvider,
    ]

    lazy var usageProviders: [any AIUsageProvider] = [
        claudeCodeProvider,
        CodexUsageProvider(),
        CopilotUsageProvider(),
        CursorUsageProvider(),
        AmpUsageProvider(),
        ZaiUsageProvider(),
        MiniMaxUsageProvider(),
        KimiUsageProvider(),
        FactoryUsageProvider(),
        DeepSeekUsageProvider(),
    ]

    private init() {}

    func notificationSource(for socketType: String) -> MuxyNotification.Source {
        let baseType: String
        if let idx = socketType.lastIndex(of: ":") {
            baseType = String(socketType[..<idx])
        } else {
            baseType = socketType
        }
        for provider in providers where provider.socketTypeKey == baseType {
            return .aiProvider(provider.id)
        }
        return .socket
    }

    func iconName(for source: MuxyNotification.Source) -> String {
        switch source {
        case .osc: "terminal"
        case let .aiProvider(id):
            providers.first { $0.id == id }?.iconName ?? "sparkles"
        case .socket: "network"
        }
    }
}
