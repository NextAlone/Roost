import Foundation
import MuxyShared
import Testing

@Suite("RoostConfig")
struct RoostConfigTests {
    @Test("decodes minimal v1 config")
    func minimalDecode() throws {
        let json = """
        { "schemaVersion": 1 }
        """
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.schemaVersion == 1)
        #expect(config.setup.isEmpty)
        #expect(config.agentPresets.isEmpty)
    }

    @Test("decodes setup commands as objects")
    func setupObjects() throws {
        let json = """
        {
          "schemaVersion": 1,
          "defaultWorkspaceLocation": ".roost/workspaces",
          "notifications": {
            "enabled": true,
            "toastEnabled": false,
            "sound": "Ping",
            "toastPosition": "Bottom Right"
          },
          "env": { "GLOBAL": "1" },
          "setup": [
            { "name": "install", "command": "pnpm install", "env": { "LOCAL": "2" } },
            { "command": "pnpm dev" }
          ],
          "teardown": [
            { "name": "cleanup", "command": "pnpm clean", "cwd": "tools" }
          ]
        }
        """
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.setup.count == 2)
        #expect(config.teardown.count == 1)
        #expect(config.defaultWorkspaceLocation == ".roost/workspaces")
        #expect(config.notifications == RoostConfigNotifications(
            enabled: true,
            toastEnabled: false,
            sound: "Ping",
            toastPosition: "Bottom Right"
        ))
        #expect(config.setup[0].name == "install")
        #expect(config.env["GLOBAL"] == "1")
        #expect(config.setup[0].env["LOCAL"] == "2")
        #expect(config.setup[1].command == "pnpm dev")
        #expect(config.setup[1].name == nil)
        #expect(config.teardown[0].cwd == "tools")
    }

    @Test("decodes agentPresets override")
    func agentPresetsOverride() throws {
        let json = """
        {
          "schemaVersion": 1,
          "agentPresets": [
            {
              "name": "Custom Claude",
              "kind": "claudeCode",
              "command": "claude --model sonnet",
              "env": {
                "CLAUDE_CONFIG_DIR": ".roost/claude",
                "CLAUDE_TOKEN": { "fromKeychain": "claude-token", "account": "work" }
              },
              "cardinality": "dedicated"
            }
          ]
        }
        """
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.agentPresets.count == 1)
        let preset = config.agentPresets[0]
        #expect(preset.name == "Custom Claude")
        #expect(preset.kind == .claudeCode)
        #expect(preset.command == "claude --model sonnet")
        #expect(preset.env["CLAUDE_CONFIG_DIR"] == ".roost/claude")
        #expect(preset.keychainEnv["CLAUDE_TOKEN"] == RoostConfigKeychainEnv(service: "claude-token", account: "work"))
        #expect(preset.cardinality == .dedicated)
    }

    @Test("env keychain references decode separately")
    func envKeychainReferencesDecodeSeparately() throws {
        let json = """
        {
          "schemaVersion": 1,
          "env": {
            "PLAIN": "ok",
            "SECRET": { "fromKeychain": "token", "account": "default" }
          },
          "setup": [
            {
              "command": "make",
              "env": {
                "LOCAL": "yes",
                "LOCAL_SECRET": { "fromKeychain": "local-token" }
              }
            }
          ]
        }
        """
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.env == ["PLAIN": "ok"])
        #expect(config.keychainEnv["SECRET"] == RoostConfigKeychainEnv(service: "token", account: "default"))
        #expect(config.setup.first?.env == ["LOCAL": "yes"])
        #expect(config.setup.first?.keychainEnv["LOCAL_SECRET"] == RoostConfigKeychainEnv(service: "local-token"))
    }

    @Test("missing schemaVersion → default 1")
    func missingSchemaVersion() throws {
        let json = "{}"
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.schemaVersion == 1)
    }

    @Test("unknown agentKind raw value rejects the entry but keeps the file")
    func unknownAgentKindIgnored() throws {
        let json = """
        {
          "schemaVersion": 1,
          "agentPresets": [
            { "name": "Future", "kind": "future-agent", "command": "future", "cardinality": "shared" },
            { "name": "Codex", "kind": "codex", "command": "codex", "cardinality": "shared" }
          ]
        }
        """
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.agentPresets.count == 1)
        #expect(config.agentPresets.first?.kind == .codex)
    }

    @Test("legacy fields don't break decode")
    func legacyFieldsTolerated() throws {
        let json = """
        {
          "schemaVersion": 1,
          "defaultWorkspaceLocation": "/tmp/wt",
          "teardown": [{ "command": "echo bye" }],
          "env": { "FOO": "bar" },
          "notifications": { "enabled": true }
        }
        """
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.schemaVersion == 1)
        #expect(config.setup.isEmpty)
        #expect(config.teardown.count == 1)
        #expect(config.env["FOO"] == "bar")
        #expect(config.defaultWorkspaceLocation == "/tmp/wt")
    }
}
