import Foundation
import MuxyShared
import RoostHostdCore

@MainActor
final class AgentScreenDetectionService {
    private weak var appState: AppState?
    private var pollTask: Task<Void, Never>?
    private var reconcilers: [UUID: AgentActivityReconciler] = [:]
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
                await self.pollPanes(appState: appState, client: client)
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollPanes(
        appState: AppState?,
        client: any RoostHostdClient
    ) async {
        guard let appState else { return }
        let panes = appState.allAgentPanes
        let paneIDs = Set(panes.map(\.id))
        reconcilers = reconcilers.filter { paneIDs.contains($0.key) }
        for pane in panes {
            if pane.hostdRuntimeOwnership != .hostdOwnedProcess {
                continue
            }
            let agentLabel = pane.agentKind.detectionLabel
            if agentLabel.isEmpty {
                continue
            }

            let result = await client.detectAgentActivity(id: pane.id, agentLabel: agentLabel)
            let previousActivityState = pane.activityState
            var reconciler = reconcilers[pane.id] ?? AgentActivityReconciler()
            let targetActivityState = reconciler.reconcile(
                detection: result,
                previousActivityState: previousActivityState
            )
            reconcilers[pane.id] = reconciler
            print("[AgentScreenDetection] pane=\(pane.id) agent=\(agentLabel) raw=\(result.state) signal=\(result.signal) previous=\(previousActivityState) target=\(targetActivityState)")
            if targetActivityState == previousActivityState { continue }

            appState.updateAgentActivity(
                paneID: pane.id,
                state: targetActivityState,
                sourceType: "screenHeuristic"
            )
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
