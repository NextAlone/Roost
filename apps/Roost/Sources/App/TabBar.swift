import SwiftUI

/// Horizontal tab strip across the top of the terminal area. Each tab is an
/// agent session; the trailing "+" opens the launcher sheet.
struct TabBar: View {
    let sessions: [LaunchedSession]
    let selectedID: LaunchedSession.ID?
    let onSelect: (LaunchedSession.ID) -> Void
    let onClose: (LaunchedSession.ID) -> Void
    let onNew: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    TabChip(
                        label: "\(index + 1). \(session.spec.agentKind)",
                        isSelected: session.id == selectedID,
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
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                Text(label)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .padding(.horizontal, 8)
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
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.2),
                    lineWidth: 1
                )
        )
    }
}
