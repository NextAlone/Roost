import Foundation
import MuxyShared
import Testing

@Suite("AgentPreset")
struct AgentPresetTests {
    @Test("catalog has a preset for every AgentKind")
    func catalogCoversAllKinds() {
        for kind in AgentKind.allCases {
            #expect(AgentPresetCatalog.preset(for: kind).kind == kind)
        }
    }

    @Test("terminal preset has no startup command")
    func terminalIsBare() {
        let preset = AgentPresetCatalog.preset(for: .terminal)
        #expect(preset.defaultCommand == nil)
        #expect(preset.requiresDedicatedWorkspace == false)
    }

    @Test("non-terminal presets have a default command")
    func agentsHaveCommand() {
        for kind in AgentKind.allCases where kind != .terminal {
            let preset = AgentPresetCatalog.preset(for: kind)
            #expect(preset.defaultCommand?.isEmpty == false)
        }
    }

    @Test("requiresDedicatedWorkspace defaults to false for all built-ins")
    func dedicatedDefaultsFalse() {
        for kind in AgentKind.allCases {
            #expect(AgentPresetCatalog.preset(for: kind).requiresDedicatedWorkspace == false)
        }
    }
}
