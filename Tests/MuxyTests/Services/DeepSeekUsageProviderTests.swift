import Foundation
import Testing

@testable import Roost

@Suite("DeepSeekUsageProvider")
struct DeepSeekUsageProviderTests {
    @Test("reads token from DEEPSEEK_API_KEY")
    func readFromEnv() throws {
        let token = try DeepSeekUsageProvider.readToken(
            env: ["DEEPSEEK_API_KEY": "sk-test-key"],
            homeDirectory: "/tmp",
            fileExists: { _ in false }
        )
        #expect(token == "sk-test-key")
    }

    @Test("reads ANTHROPIC_AUTH_TOKEN when base URL is DeepSeek")
    func readFromAnthropicTokenWhenDeepSeekURL() throws {
        let token = try DeepSeekUsageProvider.readToken(
            env: [
                "ANTHROPIC_AUTH_TOKEN": "sk-anthropic-key",
                "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
            ],
            homeDirectory: "/tmp",
            fileExists: { _ in false }
        )
        #expect(token == "sk-anthropic-key")
    }

    @Test("ignores ANTHROPIC_AUTH_TOKEN when base URL is not DeepSeek")
    func ignoresAnthropicTokenWhenNotDeepSeek() {
        #expect(throws: AIUsageAuthError.missingCredentials) {
            try DeepSeekUsageProvider.readToken(
                env: [
                    "ANTHROPIC_AUTH_TOKEN": "sk-anthropic-key",
                    "ANTHROPIC_BASE_URL": "https://api.anthropic.com",
                ],
                homeDirectory: "/tmp",
                fileExists: { _ in false }
            )
        }
    }

    @Test("prefers DEEPSEEK_API_KEY over ANTHROPIC_AUTH_TOKEN")
    func prefersDedicatedKey() throws {
        let token = try DeepSeekUsageProvider.readToken(
            env: [
                "DEEPSEEK_API_KEY": "sk-deepseek",
                "ANTHROPIC_AUTH_TOKEN": "sk-anthropic",
                "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
            ],
            homeDirectory: "/tmp",
            fileExists: { _ in false }
        )
        #expect(token == "sk-deepseek")
    }

    @Test("reads token from settings.json when env missing and URL is DeepSeek")
    func readFromSettingsJSON() throws {
        let settingsJSON = """
        {
          "env": {
            "ANTHROPIC_AUTH_TOKEN": "sk-from-settings",
            "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic"
          }
        }
        """
        let token = try DeepSeekUsageProvider.readToken(
            env: [:],
            homeDirectory: "/tmp",
            fileExists: { $0 == "/tmp/.claude/settings.json" },
            dataReader: { _ in Data(settingsJSON.utf8) }
        )
        #expect(token == "sk-from-settings")
    }

    @Test("ignores settings.json token when URL is not DeepSeek")
    func ignoresSettingsTokenWhenNotDeepSeek() {
        let settingsJSON = """
        {
          "env": {
            "ANTHROPIC_AUTH_TOKEN": "sk-from-settings",
            "ANTHROPIC_BASE_URL": "https://api.anthropic.com"
          }
        }
        """
        #expect(throws: AIUsageAuthError.missingCredentials) {
            try DeepSeekUsageProvider.readToken(
                env: [:],
                homeDirectory: "/tmp",
                fileExists: { $0 == "/tmp/.claude/settings.json" },
                dataReader: { _ in Data(settingsJSON.utf8) }
            )
        }
    }
}
