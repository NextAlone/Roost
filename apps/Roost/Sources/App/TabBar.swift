import SwiftUI

/// Horizontal tab strip across the top of the terminal area. Each tab is an
/// agent session; the trailing "+" opens the launcher sheet.
struct TabBar: View {
    let sessions: [LaunchedSession]
    let selectedID: LaunchedSession.ID?
    let unreadIDs: Set<LaunchedSession.ID>
    let onSelect: (LaunchedSession.ID) -> Void
    let onClose: (LaunchedSession.ID) -> Void
    let onNew: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    TabChip(
                        label: "\(index + 1). \(session.label)",
                        isSelected: session.id == selectedID,
                        isUnread: unreadIDs.contains(session.id),
                        onSelect: { onSelect(session.id) },
                        onClose: { onClose(session.id) }
                    )
                }

                Button(action: onNew) {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(.plain)
                .help("New session")
                .keyboardShortcut("t", modifiers: .command)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .background(.bar)
    }
}

private struct TabChip: View {
    let label: String
    let isSelected: Bool
    let isUnread: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
                    .padding(.leading, 8)
            }
            Button(action: onSelect) {
                Text(label)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .padding(.leading, isUnread ? 0 : 8)
                    .padding(.trailing, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .help("Close session")
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
    }

    private var backgroundFill: Color {
        if isSelected { return Color.accentColor.opacity(0.2) }
        return .clear
    }

    private var borderColor: Color {
        if isUnread { return Color.blue.opacity(0.8) }
        if isSelected { return Color.accentColor.opacity(0.6) }
        return Color.gray.opacity(0.2)
    }

    private var borderWidth: CGFloat {
        isUnread ? 1.5 : 1
    }
}
