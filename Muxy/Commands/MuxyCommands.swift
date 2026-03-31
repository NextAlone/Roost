import SwiftUI
import SwiftData

struct MuxyCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                guard let projectID = appState.activeProjectID else { return }
                NotificationCenter.default.post(
                    name: .muxyCreateNewTab,
                    object: nil,
                    userInfo: ["projectID": projectID]
                )
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") {
                guard let projectID = appState.activeProjectID,
                      let tabID = appState.activeTabID[projectID] else { return }
                appState.closeTab(tabID, projectID: projectID)
            }
            .keyboardShortcut("w", modifiers: .command)

            Divider()

            Button("Split Right") {
                guard let projectID = appState.activeProjectID else { return }
                NotificationCenter.default.post(
                    name: .muxySplitPane,
                    object: nil,
                    userInfo: ["projectID": projectID, "direction": SplitDirection.horizontal]
                )
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("Split Down") {
                guard let projectID = appState.activeProjectID else { return }
                NotificationCenter.default.post(
                    name: .muxySplitPane,
                    object: nil,
                    userInfo: ["projectID": projectID, "direction": SplitDirection.vertical]
                )
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Close Pane") {
                guard let projectID = appState.activeProjectID,
                      let tab = appState.activeTab(for: projectID) else { return }
                let paneCount = tab.rootNode.allPanes().count
                if paneCount > 1 {
                    tab.closeFocusedPane()
                } else {
                    appState.closeTab(tab.id, projectID: projectID)
                }
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        CommandGroup(after: .windowList) {
            ForEach(1...9, id: \.self) { index in
                Button("Tab \(index)") {
                    guard let projectID = appState.activeProjectID else { return }
                    appState.selectTabByIndex(index - 1, projectID: projectID)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
            }
        }

        CommandGroup(after: .toolbar) {
            Button("Next Pane") {
                guard let projectID = appState.activeProjectID,
                      let tab = appState.activeTab(for: projectID) else { return }
                tab.focusNextPane()
            }
            .keyboardShortcut("]", modifiers: .command)

            Button("Previous Pane") {
                guard let projectID = appState.activeProjectID,
                      let tab = appState.activeTab(for: projectID) else { return }
                tab.focusPreviousPane()
            }
            .keyboardShortcut("[", modifiers: .command)
        }
    }
}
