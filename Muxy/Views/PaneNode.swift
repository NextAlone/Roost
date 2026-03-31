import SwiftUI

struct PaneNode: View {
    let node: SplitNode
    let focusedID: UUID?
    let onFocus: (UUID) -> Void
    let onSplit: (UUID, SplitDirection) -> Void
    let onClose: (UUID) -> Void

    var body: some View {
        switch node {
        case .pane(let state):
            TerminalPane(
                state: state,
                focused: focusedID == state.id,
                onFocus: { onFocus(state.id) }
            )
        case .split(let branch):
            SplitContainer(
                branch: branch,
                focusedID: focusedID,
                onFocus: onFocus,
                onSplit: onSplit,
                onClose: onClose
            )
        }
    }
}
