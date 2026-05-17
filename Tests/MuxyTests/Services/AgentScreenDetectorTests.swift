import Foundation
import MuxyShared
import Testing
@testable import Roost
@testable import RoostHostdCore

struct ClaudeCodeDetectorTests {
    let detector = ClaudeCodeDetector()

    @Test func idleAtPrompt() {
        let screen = "Task complete.\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func idleAtSearch() {
        let screen = "\u{2315} Search\u{2026}\nsome content"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func idleAtSettingsMenu() {
        let screen = "Theme\nChoose the text style\n\n\u{276F} 1. Dark mode \u{2714}\n 2. Light mode\n\nEnter to select \u{00B7} Esc to cancel"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func idleAtHooksMenu() {
        let screen = "Hooks\n0 hooks configured\n\n\u{276F} 1. PreToolUse\n 2. PostToolUse\n\nEnter to confirm \u{00B7} Esc to cancel"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func workingEscToInterrupt() {
        let screen = "Reading file src/main.rs\nesc to interrupt\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .working)
    }

    @Test func workingCtrlCToInterrupt() {
        let screen = "Editing code\nctrl+c to interrupt\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .working)
    }

    @Test func workingSpinner() {
        let screen = "\u{273D} Pouncing\u{2026}\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .working)
    }

    @Test func workingMiddleDotSpinner() {
        let screen = "\u{00B7} Thinking\u{2026}\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .working)
    }

    @Test func staleSpinnerAbovePromptIsIdle() {
        let blankGap = String(repeating: "\n", count: 8)
        let screen = "\u{273B} Cooked for 10s" + blankGap + "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func recentSpinnerWithinPromptGapIsWorking() {
        let blankGap = String(repeating: "\n", count: 5)
        let screen = "\u{273B} Cooking for 10s" + blankGap + "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .working)
    }

    @Test func blockedDoYouWant() {
        let screen = "Do you want to run this command?\n\nYes No"
        #expect(detector.detect(screenContent: screen) == .blocked)
    }

    @Test func blockedWouldYouLike() {
        let screen = "Would you like to apply these changes?\n\n\u{276F} Yes"
        #expect(detector.detect(screenContent: screen) == .blocked)
    }

    @Test func blockedSelectionPrompt() {
        let screen = "Do you want to proceed?\n\u{276F} 1. Yes\n 2. No\n\nEsc to cancel \u{00B7} Tab to amend"
        #expect(detector.detect(screenContent: screen) == .blocked)
    }

    @Test func blockedWaitingForPermission() {
        let screen = "waiting for permission\nto run: rm -rf /tmp/test"
        #expect(detector.detect(screenContent: screen) == .blocked)
    }

    @Test func blockedTabToAmend() {
        let screen = "Tab to amend\nCtrl+E to explain"
        #expect(detector.detect(screenContent: screen) == .blocked)
    }

    @Test func blockedChatAboutThis() {
        let screen = "\u{276F} 1. Yes\n 2. No\n3. Chat about this\n\nEnter to select"
        #expect(detector.detect(screenContent: screen) == .blocked)
    }

    @Test func ctrlRToggleReturnsIdle() {
        let screen = "ctrl+r to toggle\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func contentAbovePromptBoxIgnoresPromptArea() {
        let screen = "some output\nesc to interrupt\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .working)
    }
}

struct CodexDetectorTests {
    let detector = CodexDetector()

    @Test func idleAtPrompt() {
        #expect(detector.detect(screenContent: "\u{276F} ") == .idle)
    }

    @Test func workingEscToInterrupt() {
        #expect(detector.detect(screenContent: "generating code\nesc to interrupt") == .working)
    }

    @Test func workingCtrlCToInterrupt() {
        #expect(detector.detect(screenContent: "running tools\nctrl+c to interrupt") == .working)
    }

    @Test func workingHeader() {
        #expect(detector.detect(screenContent: "\u{2022} Working (0s \u{00B7} esc\u{2026}") == .working)
    }

    @Test func blockedPressEnterToConfirm() {
        #expect(detector.detect(screenContent: "press enter to confirm or esc to cancel") == .blocked)
    }

    @Test func blockedAllowCommand() {
        #expect(detector.detect(screenContent: "allow command?\n[y/n]") == .blocked)
    }

    @Test func blockedYesY() {
        #expect(detector.detect(screenContent: "Run rm -rf /tmp?\nyes (y)") == .blocked)
    }

    @Test func blockedSubmitAnswer() {
        #expect(detector.detect(screenContent: "enter to submit answer\nesc to interrupt") == .blocked)
    }

    @Test func blockedDoYouWant() {
        #expect(detector.detect(screenContent: "Do you want to continue? yes / no") == .blocked)
    }
}

@MainActor
struct AgentScreenDetectionServiceTests {
    @Test func awaitingReturnsToRunningWhenWorkResumes() {
        let state = AgentScreenDetectionService.resolveTargetState(
            rawState: .working,
            previousActivityState: .awaiting
        )

        #expect(state == .running)
    }

    @Test func awaitingCompletesWhenWorkFinishes() {
        let state = AgentScreenDetectionService.resolveTargetState(
            rawState: .idle,
            previousActivityState: .awaiting
        )

        #expect(state == .completed)
    }
}

struct AgentDetectionStateMachineTests {
    @Test func initialReturnsFirstWorking() {
        var sm = AgentDetectionStateMachine()
        _ = sm.observe(rawState: .working, agentLabel: "codex") // count 1
        let result = sm.observe(rawState: .working, agentLabel: "codex") // count 2 -> confirm
        #expect(result == .working)
    }

    @Test func ignoresSingleFlicker() {
        var sm = AgentDetectionStateMachine()
        _ = sm.observe(rawState: .working, agentLabel: "codex") // count 1 for working
        let result = sm.observe(rawState: .idle, agentLabel: "codex") // resets to count 1 for idle
        #expect(result == nil)
    }

    @Test func confirmsAfterTwoConsecutive() {
        var sm = AgentDetectionStateMachine()
        sm.observe(rawState: .working, agentLabel: "codex") // initial working confirmed
        sm.observe(rawState: .idle, agentLabel: "codex") // count 1 for idle
        let result = sm.observe(rawState: .idle, agentLabel: "codex") // count 2 -> confirm idle
        #expect(result == .idle)
    }

    @Test func claudeWorkingSticky() {
        var sm = AgentDetectionStateMachine()
        let now = Date()
        _ = sm.observe(rawState: .working, agentLabel: "claude", now: now)
        _ = sm.observe(rawState: .working, agentLabel: "claude", now: now.addingTimeInterval(0.1)) // confirm working
        let result = sm.observe(rawState: .idle, agentLabel: "claude", now: now.addingTimeInterval(0.4))
        #expect(result == nil) // should stay working within 1.2s
    }

    @Test func claudeTransitionsAfterHoldExpires() {
        var sm = AgentDetectionStateMachine()
        let now = Date()
        _ = sm.observe(rawState: .working, agentLabel: "claude", now: now)
        _ = sm.observe(rawState: .working, agentLabel: "claude", now: now.addingTimeInterval(0.1)) // confirm working
        _ = sm.observe(rawState: .idle, agentLabel: "claude", now: now.addingTimeInterval(1.5)) // count 1 for idle
        let result = sm.observe(rawState: .idle, agentLabel: "claude", now: now.addingTimeInterval(1.5)) // count 2 -> confirm
        #expect(result == .idle)
    }

    @Test func nonClaudeNoSticky() {
        var sm = AgentDetectionStateMachine()
        let now = Date()
        _ = sm.observe(rawState: .working, agentLabel: "codex", now: now)
        _ = sm.observe(rawState: .working, agentLabel: "codex", now: now.addingTimeInterval(0.1)) // confirm working
        _ = sm.observe(rawState: .idle, agentLabel: "codex", now: now.addingTimeInterval(0.1)) // count 1 for idle
        let result = sm.observe(rawState: .idle, agentLabel: "codex", now: now.addingTimeInterval(0.1)) // count 2 -> confirm
        #expect(result == .idle)
    }

    @Test func claudeBlockedNotSticky() {
        var sm = AgentDetectionStateMachine()
        let now = Date()
        _ = sm.observe(rawState: .working, agentLabel: "claude", now: now)
        _ = sm.observe(rawState: .working, agentLabel: "claude", now: now.addingTimeInterval(0.1))
        _ = sm.observe(rawState: .blocked, agentLabel: "claude", now: now.addingTimeInterval(0.2)) // count 1
        let result = sm.observe(rawState: .blocked, agentLabel: "claude", now: now.addingTimeInterval(0.2)) // count 2 -> confirm
        #expect(result == .blocked)
    }

    @Test func resetClearsAllState() {
        var sm = AgentDetectionStateMachine()
        _ = sm.observe(rawState: .working, agentLabel: "claude")
        _ = sm.observe(rawState: .working, agentLabel: "claude")
        #expect(sm.currentState == .working)
        sm.reset()
        #expect(sm.currentState == .unknown)
        // After reset, first observation starts fresh
        _ = sm.observe(rawState: .idle, agentLabel: "claude")
        let result = sm.observe(rawState: .idle, agentLabel: "claude")
        #expect(result == .idle)
    }

    @Test func matchingCurrentStateResetsPending() {
        var sm = AgentDetectionStateMachine()
        _ = sm.observe(rawState: .working, agentLabel: "codex") // count 1
        _ = sm.observe(rawState: .working, agentLabel: "codex") // count 2 -> confirm
        _ = sm.observe(rawState: .idle, agentLabel: "codex") // count 1 for idle
        _ = sm.observe(rawState: .working, agentLabel: "codex") // matches current -> resets
        let result = sm.observe(rawState: .idle, agentLabel: "codex") // start fresh count 1
        #expect(result == nil)
    }
}
