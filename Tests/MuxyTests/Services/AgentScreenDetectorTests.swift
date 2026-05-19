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

    @Test func interruptedPromptIsIdle() {
        let screen = "\u{2022} 先查实时 SERP + Grok 综述，再用真实来源校准。\n  \u{2514} Interrupted \u{00B7} What should Claude do instead?\n\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
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

    @Test func accomplishingStatusReturnsWorking() {
        let screen = "pingping\n\n\u{2022} pong\n\n\u{2731} Crunched for 5s\n\n\u{2022} Accomplishing...\n"
        #expect(detector.detect(screenContent: screen) == .working)
    }

    @Test func channelingStatusReturnsWorking() {
        let screen = "ping\n\n\u{2731} Worked for 7s\n\n\u{2731} Channeling...(8s · thinking with high effort)\n"
        #expect(detector.detect(screenContent: screen) == .working)
    }

    @Test func completedAnswerTextContainingIngWordsIsIdle() {
        let screen = "Result notes\n\n- tool calling support varies by provider\n- background routing is optional\n\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func bulletBulletPointsWithIngWordsAbovePromptIsIdle() {
        let screen = "\u{2022} 结论：能用，但不稳；适合作备线/省钱/A-B，不适合替代原生 Claude Code 主力。\n\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func bulletPointsWithEnglishIngWordsAbovePromptIsIdle() {
        let screen = "\u{2022} background routing is optional\n\u{2022} tool calling support varies\n\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func completedDurationLineIsIdle() {
        let screen = "Ran 1 shell command\n\n\u{2022} pong\n\n\u{2731} Baked for 12s\n\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func arbitraryCompletedDurationVerbIsIdle() {
        let screen = "Ran 1 shell command\n\n\u{2022} pong\n\n\u{2731} Flurbled for 850ms\n\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func completedDurationLineStopsScanningOlderSpinner() {
        let screen = "\u{2731} Cooking for 10s\n\n\u{2731} Crunched for 12s\n\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n\u{276F} \n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}"
        #expect(detector.detect(screenContent: screen) == .idle)
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

struct AgentActivityReconcilerTests {
    @Test func awaitingReturnsToRunningWhenWorkResumes() {
        var reconciler = AgentActivityReconciler()
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .awaiting
        )

        #expect(state == .running)
    }

    @Test func idleBecomesRunningFromScreenHeuristic() {
        var reconciler = AgentActivityReconciler()
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .idle
        )

        #expect(state == .running)
    }

    @Test func runningDoesNotCompleteAfterSingleIdlePrompt() {
        var reconciler = AgentActivityReconciler()
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .idlePrompt),
            previousActivityState: .running
        )

        #expect(state == .running)
    }

    @Test func runningCompletesAfterStableIdlePrompt() {
        var reconciler = AgentActivityReconciler()
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .running
        )
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .idlePrompt),
            previousActivityState: .running
        )
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .idlePrompt),
            previousActivityState: .running
        )

        #expect(state == .completed)
    }

    @Test func staleCompletionLineDoesNotCompleteNewRun() {
        var reconciler = AgentActivityReconciler()
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .completionLine),
            previousActivityState: .running
        )

        #expect(state == .running)
    }

    @Test func stableStaleCompletionLineReturnsToIdle() {
        var reconciler = AgentActivityReconciler()
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .completionLine),
            previousActivityState: .running
        )
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .completionLine),
            previousActivityState: .running
        )

        #expect(state == .idle)
    }

    @Test func runningCompletesImmediatelyOnCompletionLineAfterWorkingEvidence() {
        var reconciler = AgentActivityReconciler()
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .running
        )
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .completionLine),
            previousActivityState: .running
        )

        #expect(state == .completed)
    }

    @Test func workingAfterIdleBlipKeepsRunning() {
        var reconciler = AgentActivityReconciler()
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .idlePrompt),
            previousActivityState: .running
        )
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .running
        )

        #expect(state == .running)
    }

    @Test func completedDoesNotBecomeRunningAfterSingleWorkingEvidence() {
        var reconciler = AgentActivityReconciler()
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .running
        )
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .completionLine),
            previousActivityState: .running
        )
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .completed
        )

        #expect(state == .completed)
    }

    @Test func screenCompletedRecoversToRunningAfterStableWorkingEvidence() {
        var reconciler = AgentActivityReconciler()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .running,
            now: now
        )
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .completionLine),
            previousActivityState: .running,
            now: now.addingTimeInterval(0.25)
        )
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .completed,
            now: now.addingTimeInterval(0.5)
        )
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .completed,
            now: now.addingTimeInterval(1)
        )

        #expect(state == .running)
    }

    @Test func completedStaysCompletedAfterRecoveryWindow() {
        var reconciler = AgentActivityReconciler()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .running,
            now: now
        )
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .completionLine),
            previousActivityState: .running,
            now: now.addingTimeInterval(0.25)
        )
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .completed,
            now: now.addingTimeInterval(6)
        )
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .working, agentLabel: "claude", signal: .workingIndicator),
            previousActivityState: .completed,
            now: now.addingTimeInterval(6.5)
        )

        #expect(state == .completed)
    }

    @Test func blockedPromptTransitionsToAwaiting() {
        var reconciler = AgentActivityReconciler()
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .blocked, agentLabel: "claude", signal: .blockedPrompt),
            previousActivityState: .running
        )

        #expect(state == .awaiting)
    }

    @Test func awaitingCompletesAfterStableIdlePrompt() {
        var reconciler = AgentActivityReconciler()
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .idlePrompt),
            previousActivityState: .awaiting
        )
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .idlePrompt),
            previousActivityState: .awaiting
        )

        #expect(state == .completed)
    }

    @Test func interruptedPromptReturnsToIdleFromAwaiting() {
        var reconciler = AgentActivityReconciler()
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .interruptedPrompt),
            previousActivityState: .awaiting
        )

        #expect(state == .idle)
    }

    @Test func stableIdlePromptWithoutRunEvidenceReturnsToIdle() {
        var reconciler = AgentActivityReconciler()
        _ = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .idlePrompt),
            previousActivityState: .running
        )
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .idlePrompt),
            previousActivityState: .running
        )

        #expect(state == .idle)
    }

    @Test func completedStaysCompletedUntilUserInteraction() {
        var reconciler = AgentActivityReconciler()
        let state = reconciler.reconcile(
            detection: AgentDetectionResult(state: .idle, agentLabel: "claude", signal: .idlePrompt),
            previousActivityState: .completed
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
        _ = sm.observe(rawState: .working, agentLabel: "codex") // initial working confirmed
        _ = sm.observe(rawState: .idle, agentLabel: "codex") // count 1 for idle
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
