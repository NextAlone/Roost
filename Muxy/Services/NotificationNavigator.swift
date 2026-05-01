import Foundation

struct NavigationContext {
    let projectID: UUID
    let worktreeID: UUID
    let worktreePath: String
    let areaID: UUID
    let tabID: UUID
}

@MainActor
enum NotificationNavigator {
    static func resolveContext(
        for paneID: UUID,
        appState: AppState,
        worktreeStore: WorktreeStore
    ) -> NavigationContext? {
        for (key, root) in appState.workspaceRoots {
            for area in root.allAreas() {
                for tab in area.tabs {
                    guard tab.content.pane?.id == paneID else { continue }
                    let path = worktreeStore.worktree(
                        projectID: key.projectID,
                        worktreeID: key.worktreeID
                    )?.path ?? area.projectPath
                    return NavigationContext(
                        projectID: key.projectID,
                        worktreeID: key.worktreeID,
                        worktreePath: path,
                        areaID: area.id,
                        tabID: tab.id
                    )
                }
            }
        }
        return nil
    }

    static func navigate(
        to notification: MuxyNotification,
        appState: AppState,
        notificationStore: NotificationStore
    ) {
        if appState.activeProjectID != notification.projectID
            || appState.activeWorktreeID[notification.projectID] != notification.worktreeID
        {
            appState.dispatch(.selectProject(
                projectID: notification.projectID,
                worktreeID: notification.worktreeID,
                worktreePath: notification.worktreePath
            ))
        }

        appState.dispatch(.focusArea(
            projectID: notification.projectID,
            areaID: notification.areaID
        ))

        appState.dispatch(.selectTab(
            projectID: notification.projectID,
            areaID: notification.areaID,
            tabID: notification.tabID
        ))

        if targetsCompletedAgent(notification, appState: appState) {
            let key = WorktreeKey(projectID: notification.projectID, worktreeID: notification.worktreeID)
            appState.clearCompletedAgentActivity(for: key)
        }

        notificationStore.markAsRead(notification.id)
    }

    private static func targetsCompletedAgent(_ notification: MuxyNotification, appState: AppState) -> Bool {
        let key = WorktreeKey(projectID: notification.projectID, worktreeID: notification.worktreeID)
        guard let root = appState.workspaceRoots[key] else { return false }
        for area in root.allAreas() {
            for tab in area.tabs where tab.id == notification.tabID {
                guard let pane = tab.content.pane,
                      pane.id == notification.paneID,
                      pane.agentKind != .terminal,
                      pane.activityState == .completed
                else { return false }
                return true
            }
        }
        return false
    }

    static func activeTabID(appState: AppState) -> UUID? {
        guard let projectID = appState.activeProjectID,
              let key = appState.activeWorktreeKey(for: projectID),
              let areaID = appState.focusedAreaID[key],
              let area = appState.workspaceRoots[key]?.findArea(id: areaID)
        else { return nil }
        return area.activeTabID
    }

    static func isActiveTab(_ tabID: UUID, appState: AppState) -> Bool {
        activeTabID(appState: appState) == tabID
    }
}
