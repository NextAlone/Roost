import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("AgentActivitySocketEvent")
struct AgentActivitySocketEventTests {
    @Test("parses needs input suffix")
    func needsInput() {
        let event = AgentActivitySocketEvent.parse(type: "codex_hook:needs_input")
        #expect(event.sourceType == "codex_hook")
        #expect(event.activityState == .needsInput)
    }

    @Test("parses completed suffix")
    func completed() {
        let event = AgentActivitySocketEvent.parse(type: "claude_hook:completed")
        #expect(event.sourceType == "claude_hook")
        #expect(event.activityState == .completed)
    }

    @Test("parses idle suffix")
    func idle() {
        let event = AgentActivitySocketEvent.parse(type: "opencode:idle")
        #expect(event.sourceType == "opencode")
        #expect(event.activityState == .idle)
    }

    @Test("legacy type keeps source and has no activity")
    func legacy() {
        let event = AgentActivitySocketEvent.parse(type: "cursor_hook")
        #expect(event.sourceType == "cursor_hook")
        #expect(event.activityState == nil)
    }

    @Test("unknown suffix keeps full type as source")
    func unknownSuffix() {
        let event = AgentActivitySocketEvent.parse(type: "custom:build_finished")
        #expect(event.sourceType == "custom:build_finished")
        #expect(event.activityState == nil)
    }
}
