import SwiftUI

/// Shown when the current bucket (Scratch or a project) has no sessions.
/// Mirrors the tab bar one-click trio (Terminal / Claude / Codex). ⌘⇧N
/// still opens the full launcher sheet for advanced targets.
struct EmptyStateView: View {
    let bucketLabel: String
    /// Same signature as TabBar: agent name for one-click; no full sheet
    /// entry is exposed here (use ⌘⇧N or the tab bar's advanced button).
    let onNew: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("No sessions in \(bucketLabel)")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                LaunchTile(
                    systemImage: "terminal",
                    assetImage: nil,
                    iconTint: .secondary,
                    label: "Terminal",
                    shortcut: "⌘T",
                    action: { onNew("shell") }
                )
                LaunchTile(
                    systemImage: nil,
                    assetImage: "AgentIcons/Claude",
                    iconTint: .orange,
                    label: "Claude Code",
                    shortcut: "⌃1",
                    action: { onNew("claude") }
                )
                LaunchTile(
                    systemImage: nil,
                    assetImage: "AgentIcons/Codex",
                    iconTint: .primary,
                    label: "Codex",
                    shortcut: "⌃2",
                    action: { onNew("codex") }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct LaunchTile: View {
    let systemImage: String?
    let assetImage: String?
    let iconTint: Color
    let label: String
    let shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let systemImage = systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 28))
                    } else if let assetImage = assetImage {
                        Image(assetImage)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                    }
                }
                .foregroundStyle(iconTint)

                Text(label)
                    .font(.callout)
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
                        )
                }
            }
            .frame(width: 120, height: 110)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.gray.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
