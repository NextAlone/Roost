import Foundation
import MuxyShared
import RoostHostdCore

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
    let hostdRuntimeOwnership: HostdRuntimeOwnership
    let createdAt: Date
    var lastState: SessionLifecycleState = .running
    var activityState: AgentActivityState
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
}
