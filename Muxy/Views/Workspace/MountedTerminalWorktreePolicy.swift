import Foundation

enum MountedTerminalWorktreePolicy {
    static func displayKeys(
        remembered: Set<WorktreeKey>,
        active: WorktreeKey?,
        available: Set<WorktreeKey>,
        agentBearing: Set<WorktreeKey> = []
    ) -> [WorktreeKey] {
        var keys = remembered.intersection(available)
        if let active, available.contains(active) {
            keys.insert(active)
        }
        keys.formUnion(agentBearing.intersection(available))
        return keys.sorted { lhs, rhs in
            if lhs.projectID != rhs.projectID {
                return lhs.projectID.uuidString < rhs.projectID.uuidString
            }
            return lhs.worktreeID.uuidString < rhs.worktreeID.uuidString
        }
    }

    static func remember(active: WorktreeKey?, available: Set<WorktreeKey>, remembered: inout Set<WorktreeKey>) {
        guard let active, available.contains(active) else { return }
        remembered.insert(active)
    }

    static func prune(available: Set<WorktreeKey>, remembered: inout Set<WorktreeKey>) {
        remembered = remembered.intersection(available)
    }
}
