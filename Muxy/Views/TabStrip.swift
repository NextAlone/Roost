import SwiftUI

struct TabStrip: View {
    let project: Project
    @Environment(AppState.self) private var appState

    private var tabs: [TerminalTab] { appState.tabsForProject(project.id) }
    private var activeID: UUID? { appState.activeTabID[project.id] }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        TabCell(
                            title: tab.title,
                            active: tab.id == activeID,
                            onSelect: { appState.selectTab(tab.id, projectID: project.id) },
                            onClose: { appState.closeTab(tab.id, projectID: project.id) }
                        )
                    }
                }
                .padding(.leading, 2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                IconButton(symbol: "square.split.2x1", size: 10) { postSplit(.horizontal) }
                IconButton(symbol: "square.split.1x2", size: 10) { postSplit(.vertical) }
                IconButton(symbol: "plus", size: 10) { appState.createTab(for: project) }
            }
            .padding(.trailing, 4)
        }
        .frame(height: 30)
        .background(MuxyTheme.surface)
    }

    private func postSplit(_ d: SplitDirection) {
        NotificationCenter.default.post(
            name: .muxySplitPane,
            object: nil,
            userInfo: ["projectID": project.id, "direction": d]
        )
    }
}

private struct TabCell: View {
    let title: String
    let active: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "terminal")
                .font(.system(size: 9))
                .foregroundStyle(active ? MuxyTheme.text : MuxyTheme.textMuted)

            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(active ? MuxyTheme.text : MuxyTheme.textMuted)
                .lineLimit(1)

            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .semibold))
                .foregroundStyle(MuxyTheme.textDim)
                .opacity(active || hovered ? 1 : 0)
                .onTapGesture(perform: onClose)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(active ? MuxyTheme.pressed : (hovered ? MuxyTheme.hover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
    }
}
