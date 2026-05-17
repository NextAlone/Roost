import Darwin
import Foundation
import MuxyShared
import os
import RoostHostdCore

private let detectionLogger = Logger(subsystem: "app.roost", category: "AgentScreenDetection")

@MainActor
final class AgentScreenDetectionService {
    private weak var appState: AppState?
    private var pollTask: Task<Void, Never>?
    private let client: any RoostHostdClient
    private let pollInterval: TimeInterval
    private var stateMachines: [UUID: AgentDetectionStateMachine] = [:]

    init(
        appState: AppState,
        client: any RoostHostdClient,
        pollInterval: TimeInterval = 0.5
    ) {
        self.appState = appState
        self.client = client
        self.pollInterval = pollInterval
    }

    deinit {
        pollTask?.cancel()
    }

    private static let logFD: Int32 = {
        let path = "/tmp/roost-detection.log"
        let fd = open(path, O_CREAT | O_WRONLY | O_APPEND, 0o644)
        return fd >= 0 ? fd : -1
    }()

    private static func log(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        if let data = line.data(using: .utf8), logFD >= 0 {
            data.withUnsafeBytes { buf in
                _ = write(logFD, buf.baseAddress, buf.count)
            }
        }
    }

    func start() {
        guard pollTask == nil else { return }
        Self.log("[AgentScreenDetection] STARTING loop, interval=\(self.pollInterval)s")
        print("[DETECT] START called")
        pollTask = Task { [pollInterval, client, weak appState] in
            while !Task.isCancelled {
                await Self.pollPanes(appState: appState, client: client, stateMachines: stateMachines)
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private static var pollCount = 0

    private static func pollPanes(
        appState: AppState?,
        client: any RoostHostdClient,
        stateMachines: [UUID: AgentDetectionStateMachine]
    ) async {
        guard let appState else { return }
        let panes = appState.allAgentPanes
        pollCount += 1
        let showDetails = pollCount <= 5 || pollCount % 6 == 0
        if showDetails {
            Self.log("[AgentScreenDetection] poll #\(pollCount): \(panes.count) panes")
        }
        for pane in panes {
            if pane.hostdRuntimeOwnership != .hostdOwnedProcess {
                if showDetails { Self.log("[AgentScreenDetection] skip pane: ownership=\(pane.hostdRuntimeOwnership.rawValue)") }
                continue
            }
            let agentLabel = pane.agentKind.detectionLabel
            if agentLabel.isEmpty {
                if showDetails { Self.log("[AgentScreenDetection] skip pane: no label for kind=\(String(describing: pane.agentKind))") }
                continue
            }

            let result = await client.detectAgentActivity(id: pane.id, agentLabel: agentLabel)
            let rawState = result.state
            let previousActivityState = pane.activityState

            if showDetails {
                Self.log("[AgentScreenDetection] pane \(agentLabel): raw=\(rawState.label) prev=\(previousActivityState.rawValue)")
            }

            let targetActivityState = resolveTargetState(
                rawState: rawState,
                previousActivityState: previousActivityState
            )
            if targetActivityState == previousActivityState { continue }

            Self.log("[AgentScreenDetection] STATE: \(previousActivityState.rawValue) → \(targetActivityState.rawValue)")
            appState.updateAgentActivity(
                paneID: pane.id,
                state: targetActivityState,
                sourceType: "screenHeuristic"
            )
        }
    }

    private static func resolveTargetState(
        rawState: AgentDetectionState,
        previousActivityState: AgentActivityState
    ) -> AgentActivityState {
        switch rawState {
        case .working:
            if previousActivityState == .idle || previousActivityState == .completed {
                return .running
            }
            return previousActivityState
        case .blocked:
            return .awaiting
        case .idle:
            if previousActivityState == .running {
                return .completed
            }
            return .idle
        case .unknown:
            return previousActivityState
        }
    }
}

extension AgentKind {
    var detectionLabel: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        default: ""
        }
    }
}
