import Foundation
import Testing

@Suite("Visible branding")
struct VisibleBrandingTests {
    @Test("mobile pairing and settings copy use Roost")
    func mobilePairingAndSettingsCopyUseRoost() throws {
        let coordinator = try resourceText("Muxy/Services/PairingRequestCoordinator.swift")
        let settings = try resourceText("Muxy/Views/Settings/MobileSettingsView.swift")

        #expect(coordinator.contains("access to Roost"))
        #expect(settings.contains("Roost listens"))
        #expect(!coordinator.contains("access to Muxy"))
        #expect(!settings.contains("Muxy listens"))
    }

    @Test("external user agents use Roost")
    func externalUserAgentsUseRoost() throws {
        let markdown = try resourceText("Muxy/Views/Markdown/MarkdownRemoteImageSchemeHandler.swift")
        let factory = try resourceText("Muxy/Services/Providers/FactoryUsageProvider.swift")
        let kimi = try resourceText("Muxy/Services/Providers/KimiUsageProvider.swift")

        #expect(markdown.contains("\"Roost/1.0 (Markdown Preview)\""))
        #expect(factory.contains("forHTTPHeaderField: \"User-Agent\")"))
        #expect(factory.contains("request.setValue(\"Roost\""))
        #expect(kimi.contains("request.setValue(\"Roost\""))
        #expect(!markdown.contains("\"Muxy/1.0 (Markdown Preview)\""))
        #expect(!factory.contains("request.setValue(\"Muxy\""))
        #expect(!kimi.contains("request.setValue(\"Muxy\""))
    }

    @Test("remote worktree errors use Roost")
    func remoteWorktreeErrorsUseRoost() throws {
        let source = try resourceText("Muxy/Services/RemoteServerDelegate.swift")

        #expect(source.contains("managed outside Roost"))
        #expect(!source.contains("managed outside Muxy"))
    }

    @Test("provider backup filenames use Roost")
    func providerBackupFilenamesUseRoost() throws {
        let claude = try resourceText("Muxy/Services/Providers/ClaudeCodeProvider.swift")
        let codex = try resourceText("Muxy/Services/Providers/CodexProvider.swift")
        let cursor = try resourceText("Muxy/Services/Providers/CursorProvider.swift")

        #expect(claude.contains(".roost-backup"))
        #expect(codex.contains(".roost-backup"))
        #expect(cursor.contains(".roost-backup"))
        #expect(!claude.contains(".muxy-backup"))
        #expect(!codex.contains(".muxy-backup"))
        #expect(!cursor.contains(".muxy-backup"))
    }

    @Test("editor performance debug environment uses Roost primary name")
    func editorPerformanceDebugEnvironmentUsesRoostPrimaryName() throws {
        let source = try resourceText("Muxy/Views/Editor/CodeEditorRepresentable.swift")

        #expect(source.contains("ROOST_EDITOR_PERF"))
        #expect(source.contains("MUXY_EDITOR_PERF"))
    }

    @Test("notification setup docs prefer Roost environment names")
    func notificationSetupDocsPreferRoostEnvironmentNames() throws {
        let docs = try resourceText("docs/notification-setup.md")

        #expect(docs.contains("`ROOST_SOCKET_PATH`"))
        #expect(docs.contains("$ROOST_PANE_ID"))
        #expect(docs.contains("roost-claude-hook.sh"))
        #expect(docs.contains("opencode-roost-plugin.js"))
        #expect(!docs.contains("current integration contract for inherited hook scripts"))
        #expect(!docs.contains("muxy-claude-hook.sh"))
        #expect(!docs.contains("opencode-muxy-plugin.js"))
    }

    private func resourceText(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
