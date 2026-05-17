import Foundation
import MuxyShared
import RoostHostdCore

struct AgentActivityReconciler {
    private var idleEvidenceCount = 0
    private var workingEvidenceCount = 0
    private var hasActiveRunEvidence = false
    private var completedByScreenHeuristic = false
    private var screenCompletedAt: Date?

    mutating func reconcile(
        detection: AgentDetectionResult,
        previousActivityState: AgentActivityState,
        now: Date = Date()
    ) -> AgentActivityState {
        if previousActivityState == .exited {
            resetTransientEvidence()
            return .exited
        }

        updateEvidenceCounts(signal: detection.signal)

        switch previousActivityState {
        case .idle:
            hasActiveRunEvidence = false
            completedByScreenHeuristic = false
            screenCompletedAt = nil
            return idleTarget(for: detection)
        case .running:
            return runningTarget(for: detection, now: now)
        case .awaiting:
            return awaitingTarget(for: detection, now: now)
        case .completed:
            return completedTarget(for: detection, now: now)
        case .exited:
            return .exited
        }
    }

    private mutating func idleTarget(for detection: AgentDetectionResult) -> AgentActivityState {
        switch detection.signal {
        case .workingIndicator:
            hasActiveRunEvidence = true
            return .running
        case .blockedPrompt:
            hasActiveRunEvidence = true
            return .awaiting
        default:
            return .idle
        }
    }

    private mutating func runningTarget(for detection: AgentDetectionResult, now: Date) -> AgentActivityState {
        switch detection.signal {
        case .workingIndicator:
            hasActiveRunEvidence = true
            completedByScreenHeuristic = false
            screenCompletedAt = nil
            return .running
        case .blockedPrompt:
            hasActiveRunEvidence = true
            completedByScreenHeuristic = false
            screenCompletedAt = nil
            return .awaiting
        case .completionLine:
            guard hasActiveRunEvidence else {
                if idleEvidenceCount >= 2 {
                    resetStaleRunEvidence()
                    return .idle
                }
                return .running
            }
            markScreenCompleted(at: now)
            return .completed
        case .idlePrompt:
            if idleEvidenceCount >= 2 {
                if hasActiveRunEvidence {
                    markScreenCompleted(at: now)
                    return .completed
                }
                resetStaleRunEvidence()
                return .idle
            }
            return .running
        case .interruptedPrompt:
            resetStaleRunEvidence()
            return .idle
        case .unknown:
            return .running
        }
    }

    private mutating func awaitingTarget(for detection: AgentDetectionResult, now: Date) -> AgentActivityState {
        switch detection.signal {
        case .workingIndicator:
            hasActiveRunEvidence = true
            completedByScreenHeuristic = false
            screenCompletedAt = nil
            return .running
        case .blockedPrompt:
            hasActiveRunEvidence = true
            return .awaiting
        case .completionLine:
            guard hasActiveRunEvidence else { return .awaiting }
            markScreenCompleted(at: now)
            return .completed
        case .idlePrompt:
            if idleEvidenceCount >= 2 {
                markScreenCompleted(at: now)
                return .completed
            }
            return .awaiting
        case .interruptedPrompt:
            resetStaleRunEvidence()
            return .idle
        case .unknown:
            return .awaiting
        }
    }

    private mutating func completedTarget(for detection: AgentDetectionResult, now: Date) -> AgentActivityState {
        guard detection.signal == .workingIndicator else {
            return .completed
        }
        guard completedByScreenHeuristic,
              let completedAt = screenCompletedAt,
              now.timeIntervalSince(completedAt) <= 5,
              workingEvidenceCount >= 2
        else {
            return .completed
        }
        hasActiveRunEvidence = true
        completedByScreenHeuristic = false
        screenCompletedAt = nil
        return .running
    }

    private mutating func updateEvidenceCounts(signal: AgentScreenSignal) {
        switch signal {
        case .idlePrompt, .interruptedPrompt:
            idleEvidenceCount += 1
            workingEvidenceCount = 0
        case .workingIndicator:
            workingEvidenceCount += 1
            idleEvidenceCount = 0
        case .blockedPrompt:
            idleEvidenceCount = 0
            workingEvidenceCount = 0
        case .completionLine:
            idleEvidenceCount += 1
            workingEvidenceCount = 0
        case .unknown:
            resetTransientEvidence()
        }
    }

    private mutating func markScreenCompleted(at now: Date) {
        hasActiveRunEvidence = false
        completedByScreenHeuristic = true
        screenCompletedAt = now
        resetTransientEvidence()
    }

    private mutating func resetStaleRunEvidence() {
        hasActiveRunEvidence = false
        completedByScreenHeuristic = false
        screenCompletedAt = nil
        resetTransientEvidence()
    }

    private mutating func resetTransientEvidence() {
        idleEvidenceCount = 0
        workingEvidenceCount = 0
    }
}
