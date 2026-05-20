import Foundation
import MuxyShared
import os
import RoostHostdCore

private let logger = Logger(subsystem: "app.roost", category: "AgentScreenDetection")

@MainActor
final class AgentScreenDetectionService {
    private weak var appState: AppState?
    private let client: any RoostHostdClient
    private var supervisorTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var activeSubscriptionIDs: Set<UUID> = []
    private var reconcilers: [UUID: AgentActivityReconciler] = [:]

    init(appState: AppState, client: any RoostHostdClient) {
        self.appState = appState
        self.client = client
    }

    deinit {
        supervisorTask?.cancel()
        connectionTask?.cancel()
    }

    func start() {
        guard supervisorTask == nil else { return }
        supervisorTask = Task { [weak self] in await self?.runSupervisor() }
    }

    func stop() {
        supervisorTask?.cancel()
        supervisorTask = nil
        connectionTask?.cancel()
        connectionTask = nil
        activeSubscriptionIDs = []
    }

    private func runSupervisor() async {
        while !Task.isCancelled {
            let snapshot = currentSubscriptionSnapshot()
            let snapshotIDs = Set(snapshot.keys)
            let connectionAlive = connectionTask != nil
            if snapshotIDs.isEmpty {
                if connectionAlive {
                    connectionTask?.cancel()
                    connectionTask = nil
                    activeSubscriptionIDs = []
                }
            } else if !connectionAlive || snapshotIDs != activeSubscriptionIDs {
                connectionTask?.cancel()
                activeSubscriptionIDs = snapshotIDs
                connectionTask = Task { [weak self] in
                    await self?.runConnection(subscriptions: snapshot)
                    await self?.clearConnectionTask()
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        connectionTask?.cancel()
        connectionTask = nil
    }

    private func clearConnectionTask() {
        connectionTask = nil
    }

    private func currentSubscriptionSnapshot() -> [UUID: String] {
        guard let appState else { return [:] }
        var out: [UUID: String] = [:]
        for pane in appState.allAgentPanes
            where pane.hostdRuntimeOwnership == .hostdOwnedProcess && !pane.agentKind.detectionLabel.isEmpty
        {
            out[pane.id] = pane.agentKind.detectionLabel
        }
        return out
    }

    private func runConnection(subscriptions: [UUID: String]) async {
        var delay: UInt64 = 2_000_000_000
        while !Task.isCancelled {
            do {
                try await consumeEvents(subscriptions: subscriptions)
                return
            } catch {
                let retrySeconds = delay / 1_000_000_000
                logger.warning("[subscribe] lost: \(error.localizedDescription, privacy: .public), retry in \(retrySeconds)s")
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 30_000_000_000)
            }
        }
    }

    private func consumeEvents(subscriptions: [UUID: String]) async throws {
        guard let appState else { return }
        reconcilers = reconcilers.filter { subscriptions[$0.key] != nil }
        for try await event in client.subscribeAgentActivity(subscriptions: subscriptions) {
            guard !Task.isCancelled else { return }
            guard let pane = appState.allAgentPanes.first(where: { $0.id == event.paneID }) else { continue }
            var reconciler = reconcilers[event.paneID] ?? AgentActivityReconciler()
            let targetState = reconciler.reconcile(detection: event.detection, previousActivityState: pane.activityState)
            reconcilers[event.paneID] = reconciler
            let detect = "\(event.detection.state.label)/\(event.detection.signal.rawValue)"
            logger.debug("[subscribe] \(event.paneID) detect=\(detect) target=\(targetState.rawValue)")
            guard targetState != pane.activityState else { continue }
            appState.updateAgentActivity(paneID: event.paneID, state: targetState, sourceType: "screenHeuristic")
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
