import Foundation
import MuxyShared
import Testing

@Suite("AgentKind")
struct AgentKindTests {
    @Test("Codable round-trips all cases")
    func codableRoundTrip() throws {
        let original = AgentKind.allCases
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([AgentKind].self, from: data)
        #expect(decoded == original)
    }

    @Test("decodes legacy raw value 'terminal'")
    func decodesTerminal() throws {
        let json = "[\"terminal\"]"
        let decoded = try JSONDecoder().decode([AgentKind].self, from: Data(json.utf8))
        #expect(decoded == [.terminal])
    }

    @Test("display names are non-empty")
    func displayNames() {
        for kind in AgentKind.allCases {
            #expect(!kind.displayName.isEmpty)
        }
    }

    @Test("unknown raw value throws")
    func unknownThrows() {
        let json = "[\"copilot\"]"
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode([AgentKind].self, from: Data(json.utf8))
        }
    }

    @Test("raw values are stable for snapshot backward compatibility")
    func rawValuesAreStable() {
        #expect(AgentKind.terminal.rawValue == "terminal")
        #expect(AgentKind.claudeCode.rawValue == "claudeCode")
        #expect(AgentKind.codex.rawValue == "codex")
        #expect(AgentKind.geminiCli.rawValue == "geminiCli")
        #expect(AgentKind.openCode.rawValue == "openCode")
    }

    @Test("iconSystemName is non-empty for all cases")
    func iconNonEmpty() {
        for kind in AgentKind.allCases {
            #expect(!kind.iconSystemName.isEmpty)
        }
    }

    @Test("icon mapping matches expected SF Symbols")
    func iconMapping() {
        #expect(AgentKind.terminal.iconSystemName == "terminal")
        #expect(AgentKind.claudeCode.iconSystemName == "sparkles")
        #expect(AgentKind.codex.iconSystemName == "brain")
        #expect(AgentKind.geminiCli.iconSystemName == "star.circle")
        #expect(AgentKind.openCode.iconSystemName == "hammer")
    }
}
