import Foundation
import MuxyShared
import RoostHostdCore

@MainActor
final class AgentScreenDetectionService {
    private weak var appState: AppState?
    private var pollTask: Task<Void, Never>?
    private let client: any RoostHostdClient
    private let pollInterval: TimeInterval

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

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [pollInterval, client, weak appState] in
            while !Task.isCancelled {
                await Self.pollPanes(appState: appState, client: client)
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private static func pollPanes(
        appState: AppState?,
        client: any RoostHostdClient
    ) async {
        guard let appState else { return }
        let panes = appState.allAgentPanes
        for pane in panes {
            if pane.hostdRuntimeOwnership != .hostdOwnedProcess {
                continue
            }
            let agentLabel = pane.agentKind.detectionLabel
            if agentLabel.isEmpty {
                continue
            }

            let result = await client.detectAgentActivity(id: pane.id, agentLabel: agentLabel)
            let rawState = result.state
            let previousActivityState = pane.activityState

            let targetActivityState = resolveTargetState(
                rawState: rawState,
                previousActivityState: previousActivityState
            )
            if targetActivityState == previousActivityState { continue }

            appState.updateAgentActivity(
                paneID: pane.id,
                state: targetActivityState,
                sourceType: "screenHeuristic"
            )
        }
    }

    static func resolveTargetState(
        rawState: AgentDetectionState,
        previousActivityState: AgentActivityState
    ) -> AgentActivityState {
        switch rawState {
        case .working:
            if previousActivityState == .idle || previousActivityState == .completed || previousActivityState == .awaiting {
                return .running
            }
            return previousActivityState
        case .blocked:
            return .awaiting
        case .idle:
            if previousActivityState == .running || previousActivityState == .awaiting {
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
