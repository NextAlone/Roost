import SwiftUI

/// Horizontal tab strip across the top of the terminal area. Each tab is an
/// agent session; the trailing "+" opens the launcher sheet.
struct TabBar: View {
    let sessions: [LaunchedSession]
    let selectedID: LaunchedSession.ID?
    let unreadIDs: Set<LaunchedSession.ID>
    let onSelect: (LaunchedSession.ID) -> Void
    let onClose: (LaunchedSession.ID) -> Void
    /// Fire with agent name (`"shell"`, `"claude"`, `"codex"`) for one-click
    /// new-session buttons; fire with `nil` for the advanced "New session…"
    /// entry (opens the launcher sheet).
    let onNew: (String?) -> Void

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

                Divider().frame(height: 22).padding(.horizontal, 6)

                NewTabButton(
                    systemImage: "terminal",
                    iconTint: .secondary,
                    label: "Terminal",
                    tooltip: "New terminal (⌘T)",
                    action: { onNew("shell") }
                )
                NewTabButton(
                    assetImage: "AgentIcons/Claude",
                    iconTint: .orange,
                    label: "Claude Code",
                    tooltip: "New Claude Code (⌃1)",
                    action: { onNew("claude") }
                )
                NewTabButton(
                    assetImage: "AgentIcons/Codex",
                    iconTint: .primary,
                    label: "Codex",
                    tooltip: "New Codex (⌃2)",
                    action: { onNew("codex") }
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}

private struct NewTabButton: View {
    var systemImage: String? = nil
    var assetImage: String? = nil
    var iconTint: Color = .secondary
    let label: String?
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.callout)
                        .foregroundStyle(iconTint)
                } else if let assetImage = assetImage {
                    Image(assetImage)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(iconTint)
                }
                if let label = label {
                    Text(label)
                        .font(.callout)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

private struct TabChip: View {
    let label: String
    let isSelected: Bool
    let isUnread: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 7, height: 7)
                    .padding(.leading, 10)
            }
            Button(action: onSelect) {
                Text(label)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .padding(.leading, isUnread ? 0 : 10)
                    .padding(.trailing, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("Close session")
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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
