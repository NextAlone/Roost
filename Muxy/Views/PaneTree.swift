import SwiftUI

struct PaneTree: View {
    let tab: TerminalTab
    let projectPath: String
    let isActiveTab: Bool

    var body: some View {
        PaneNode(
            node: tab.rootNode,
            focusedID: tab.focusedPaneID,
            isActiveTab: isActiveTab,
            onFocus: { tab.focusedPaneID = $0 },
            onSplit: { id, dir in
                splitPane(id, direction: dir)
            },
            onClose: { id in
                guard let root = tab.rootNode.removing(paneID: id) else { return }
                tab.rootNode = root
                tab.focusedPaneID = root.allPanes().first?.id
            }
        )
    }

    func splitPane(_ paneID: UUID, direction: SplitDirection) {
        let pane = TerminalPaneState(projectPath: projectPath)
        tab.rootNode = tab.rootNode.splitting(paneID: paneID, direction: direction, newPane: pane)
        tab.focusedPaneID = pane.id
    }
}
