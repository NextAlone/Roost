import Foundation
import SwiftUI

@MainActor
@Observable
final class AppState {
    var activeProjectID: UUID?
    var tabs: [UUID: [TerminalTab]] = [:]
    var activeTabID: [UUID: UUID] = [:]

    func tabsForProject(_ projectID: UUID) -> [TerminalTab] {
        tabs[projectID] ?? []
    }

    func activeTab(for projectID: UUID) -> TerminalTab? {
        guard let tabID = activeTabID[projectID] else { return nil }
        return tabs[projectID]?.first { $0.id == tabID }
    }

    func createTab(for project: Project) {
        let pane = TerminalPaneState(projectPath: project.path)
        let tab = TerminalTab(pane: pane)
        tabs[project.id, default: []].append(tab)
        activeTabID[project.id] = tab.id
    }

    func closeTab(_ tabID: UUID, projectID: UUID) {
        tabs[projectID]?.removeAll { $0.id == tabID }
        if activeTabID[projectID] == tabID {
            activeTabID[projectID] = tabs[projectID]?.last?.id
        }
        if tabsForProject(projectID).isEmpty {
            activeProjectID = nil
        }
    }

    func selectTab(_ tabID: UUID, projectID: UUID) {
        activeTabID[projectID] = tabID
    }

    func selectTabByIndex(_ index: Int, projectID: UUID) {
        let projectTabs = tabsForProject(projectID)
        guard index >= 0, index < projectTabs.count else { return }
        activeTabID[projectID] = projectTabs[index].id
    }

    func ensureTabExists(for project: Project) {
        if tabsForProject(project.id).isEmpty {
            createTab(for: project)
        }
    }

    func removeProject(_ projectID: UUID) {
        tabs.removeValue(forKey: projectID)
        activeTabID.removeValue(forKey: projectID)
        if activeProjectID == projectID {
            activeProjectID = nil
        }
    }
}
