import Foundation
import MuxyShared

@MainActor
@Observable
final class TerminalPaneState: Identifiable {
    let id = UUID()
    let projectPath: String
    var title: String
    let startupCommand: String?
    let externalEditorFilePath: String?
    let agentKind: AgentKind
    let createdAt: Date
    var lastState: SessionLifecycleState = .running
    let searchState = TerminalSearchState()
    @ObservationIgnored private var titleDebounceTask: Task<Void, Never>?

    init(
        projectPath: String,
        title: String = "Terminal",
        startupCommand: String? = nil,
        externalEditorFilePath: String? = nil,
        agentKind: AgentKind = .terminal,
        createdAt: Date = Date()
    ) {
        self.projectPath = projectPath
        self.title = title
        self.startupCommand = startupCommand
        self.externalEditorFilePath = externalEditorFilePath
        self.agentKind = agentKind
        self.createdAt = createdAt
    }

    func setTitle(_ newTitle: String) {
        titleDebounceTask?.cancel()
        titleDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.title != newTitle else { return }
            self.title = newTitle
        }
    }
}
