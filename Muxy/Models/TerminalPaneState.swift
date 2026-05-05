import Foundation
import MuxyShared
import RoostHostdCore

enum HostdAttachState: Equatable {
    case inactive
    case preparing
    case ready
    case failed(String)
}

@MainActor
@Observable
final class TerminalPaneState: Identifiable {
    let id: UUID
    let projectPath: String
    var title: String
    var currentWorkingDirectory: String?
    let startupCommand: String?
    let startupCommandInteractive: Bool
    let env: [String: String]
    let externalEditorFilePath: String?
    let agentKind: AgentKind
    var hostdRuntimeOwnership: HostdRuntimeOwnership {
        didSet {
            guard hostdRuntimeOwnership != oldValue else { return }
            hostdAttachState = Self.initialHostdAttachState(
                agentKind: agentKind,
                ownership: hostdRuntimeOwnership
            )
        }
    }

    var hostdAttachState: HostdAttachState
    let createdAt: Date
    var lastState: SessionLifecycleState = .running
    var activityState: AgentActivityState
    var previousActivityState: AgentActivityState?
    let searchState = TerminalSearchState()
    @ObservationIgnored private var titleDebounceTask: Task<Void, Never>?

    init(
        id: UUID = UUID(),
        projectPath: String,
        title: String = "Terminal",
        initialWorkingDirectory: String? = nil,
        startupCommand: String? = nil,
        startupCommandInteractive: Bool = false,
        env: [String: String] = [:],
        externalEditorFilePath: String? = nil,
        agentKind: AgentKind = .terminal,
        hostdRuntimeOwnership: HostdRuntimeOwnership = .appOwnedMetadataOnly,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectPath = projectPath
        self.title = title
        self.currentWorkingDirectory = initialWorkingDirectory
        self.startupCommand = startupCommand
        self.startupCommandInteractive = startupCommandInteractive
        self.env = env
        self.externalEditorFilePath = externalEditorFilePath
        self.agentKind = agentKind
        self.hostdRuntimeOwnership = hostdRuntimeOwnership
        self.hostdAttachState = Self.initialHostdAttachState(
            agentKind: agentKind,
            ownership: hostdRuntimeOwnership
        )
        self.createdAt = createdAt
        activityState = agentKind == .terminal ? .running : .idle
    }

    func setTitle(_ newTitle: String) {
        titleDebounceTask?.cancel()
        titleDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.title != newTitle else { return }
            self.title = newTitle
        }
    }

    func setWorkingDirectory(_ path: String) {
        currentWorkingDirectory = path
    }

    @discardableResult
    func acknowledgeUserInteraction() -> Bool {
        guard agentKind != .terminal else { return false }
        switch activityState {
        case .completed:
            activityState = .idle
            previousActivityState = nil
            return true
        case .needsInput:
            activityState = previousActivityState ?? .idle
            previousActivityState = nil
            return true
        default:
            return false
        }
    }

    func markHostdAttachPreparing() {
        guard hostdRuntimeOwnership == .hostdOwnedProcess, agentKind != .terminal else {
            hostdAttachState = .inactive
            return
        }
        hostdAttachState = .preparing
    }

    func markHostdAttachReady() {
        guard hostdRuntimeOwnership == .hostdOwnedProcess, agentKind != .terminal else {
            hostdAttachState = .inactive
            return
        }
        hostdAttachState = .ready
    }

    func markHostdAttachFailed(_ message: String) {
        guard hostdRuntimeOwnership == .hostdOwnedProcess, agentKind != .terminal else {
            hostdAttachState = .inactive
            return
        }
        hostdAttachState = .failed(message)
    }

    private static func initialHostdAttachState(agentKind: AgentKind, ownership: HostdRuntimeOwnership) -> HostdAttachState {
        guard ownership == .hostdOwnedProcess, agentKind != .terminal else { return .inactive }
        return .preparing
    }
}
