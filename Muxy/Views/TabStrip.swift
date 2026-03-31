import SwiftUI

struct TabStrip: View {
    let project: Project?
    let onAddProject: () -> Void
    @Environment(AppState.self) private var appState

    private var tabs: [TerminalTab] {
        guard let project else { return [] }
        return appState.tabsForProject(project.id)
    }
    private var activeID: UUID? {
        guard let project else { return nil }
        return appState.activeTabID[project.id]
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Spacer()
                IconButton(symbol: "plus", action: onAddProject)
            }
            .padding(.horizontal, 8)
            .frame(width: 160)

            Rectangle().fill(MuxyTheme.border).frame(width: 1)

            ForEach(tabs) { tab in
                TabCell(
                    title: tab.title,
                    active: tab.id == activeID,
                    onSelect: { appState.selectTab(tab.id, projectID: project!.id) },
                    onClose: { appState.closeTab(tab.id, projectID: project!.id) }
                )
            }

            Spacer(minLength: 0)

            if let project {
                HStack(spacing: 0) {
                    IconButton(symbol: "square.split.2x1") { postSplit(.horizontal) }
                    IconButton(symbol: "square.split.1x2") { postSplit(.vertical) }
                    IconButton(symbol: "plus") { appState.createTab(for: project) }
                }
                .padding(.trailing, 4)
            }
        }
        .frame(height: 32)
        .background(MuxyTheme.bg)
    }

    private func postSplit(_ d: SplitDirection) {
        guard let project else { return }
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
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(active ? MuxyTheme.text : MuxyTheme.textMuted)

                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(active ? MuxyTheme.text : MuxyTheme.textMuted)
                    .lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 28)
            .frame(maxWidth: 200, alignment: .leading)
            .frame(height: 32)
            .overlay(alignment: .trailing) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MuxyTheme.textDim)
                    .padding(.trailing, 10)
                    .opacity(active || hovered ? 1 : 0)
                    .onTapGesture(perform: onClose)
            }
            .overlay(alignment: .top) {
                if active {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
            .background(active ? MuxyTheme.surface : .clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .onHover { hovered = $0 }

            Rectangle().fill(MuxyTheme.border).frame(width: 1)
        }
    }
}
