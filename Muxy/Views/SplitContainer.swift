import SwiftUI
import AppKit

struct SplitContainer: View {
    let branch: SplitBranch
    let focusedID: UUID?
    let isActiveTab: Bool
    let onFocus: (UUID) -> Void
    let onSplit: (UUID, SplitDirection) -> Void
    let onClose: (UUID) -> Void

    var body: some View {
        GeometryReader { geo in
            let h = branch.direction == .horizontal
            let total = h ? geo.size.width : geo.size.height
            let first = max(0, total * branch.ratio - 0.5)
            let second = max(0, total * (1 - branch.ratio) - 0.5)

            let layout = h ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))

            layout {
                child(branch.first)
                    .frame(width: h ? first : nil, height: h ? nil : first)

                Color.clear
                    .frame(width: h ? 1 : nil, height: h ? nil : 1)
                    .overlay(Rectangle().fill(MuxyTheme.border))
                    .overlay {
                        Color.clear
                            .frame(width: h ? 5 : nil, height: h ? nil : 5)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { v in
                                        let delta = h ? v.translation.width : v.translation.height
                                        branch.ratio = min(max((total * branch.ratio + delta) / total, 0.15), 0.85)
                                    }
                            )
                            .onHover { on in
                                if on { (h ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() }
                                else { NSCursor.pop() }
                            }
                    }

                child(branch.second)
                    .frame(width: h ? second : nil, height: h ? nil : second)
            }
        }
    }

    private func child(_ node: SplitNode) -> some View {
        PaneNode(node: node, focusedID: focusedID, isActiveTab: isActiveTab, onFocus: onFocus, onSplit: onSplit, onClose: onClose)
    }
}
