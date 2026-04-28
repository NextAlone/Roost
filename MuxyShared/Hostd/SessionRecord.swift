import Foundation

public struct SessionRecord: Sendable, Codable, Hashable {
    public let id: UUID
    public let projectID: UUID
    public let worktreeID: UUID
    public let workspacePath: String
    public let agentKind: AgentKind
    public let command: String?
    public let createdAt: Date
    public let lastState: SessionLifecycleState

    public init(
        id: UUID,
        projectID: UUID,
        worktreeID: UUID,
        workspacePath: String,
        agentKind: AgentKind,
        command: String?,
        createdAt: Date,
        lastState: SessionLifecycleState
    ) {
        self.id = id
        self.projectID = projectID
        self.worktreeID = worktreeID
        self.workspacePath = workspacePath
        self.agentKind = agentKind
        self.command = command
        self.createdAt = createdAt
        self.lastState = lastState
    }
}
