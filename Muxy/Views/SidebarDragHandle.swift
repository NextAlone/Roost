import SwiftUI
import AppKit

struct SidebarDragHandle: View {
    @Binding var width: CGFloat
    @State private var startWidth: CGFloat = 0

    var body: some View {
        Color.clear
            .frame(width: 4)
            .contentShape(Rectangle())
            .gesture(drag)
            .onHover { h in
                if h { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                if startWidth == 0 { startWidth = width }
                width = min(max(startWidth + v.translation.width, 180), 360)
            }
            .onEnded { _ in startWidth = 0 }
    }
}
