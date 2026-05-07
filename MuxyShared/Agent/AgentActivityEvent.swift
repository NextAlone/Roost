import Foundation

public struct AgentActivityEvent: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let paneID: UUID
    public let projectID: UUID?
    public let worktreeID: UUID?
    public let timestamp: Date
    public let from: AgentActivityState?
    public let to: AgentActivityState
    public let sourceType: String?

    public init(
        id: UUID = UUID(),
        paneID: UUID,
        projectID: UUID? = nil,
        worktreeID: UUID? = nil,
        timestamp: Date = Date(),
        from: AgentActivityState? = nil,
        to: AgentActivityState,
        sourceType: String? = nil
    ) {
        self.id = id
        self.paneID = paneID
        self.projectID = projectID
        self.worktreeID = worktreeID
        self.timestamp = timestamp
        self.from = from
        self.to = to
        self.sourceType = sourceType
    }
}
