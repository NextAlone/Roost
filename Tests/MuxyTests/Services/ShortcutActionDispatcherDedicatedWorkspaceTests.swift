import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("ShortcutActionDispatcher dedicated workspace routing")
struct ShortcutActionDispatcherDedicatedWorkspaceTests {
    @Test("routes when preset.requiresDedicatedWorkspace == true")
    func routesWhenFlagTrue() {
        let lookup: (AgentKind) -> AgentPreset = { _ in
            AgentPreset(kind: .claudeCode, defaultCommand: "claude", requiresDedicatedWorkspace: true)
        }
        #expect(
            ShortcutActionDispatcher.shouldRouteToWorkspaceCreation(
                kind: .claudeCode,
                presetLookup: lookup
            )
        )
    }

    @Test("does not route when flag false")
    func staysWhenFlagFalse() {
        let lookup: (AgentKind) -> AgentPreset = { kind in
            AgentPreset(kind: kind, defaultCommand: "claude", requiresDedicatedWorkspace: false)
        }
        #expect(
            !ShortcutActionDispatcher.shouldRouteToWorkspaceCreation(
                kind: .claudeCode,
                presetLookup: lookup
            )
        )
    }
}
