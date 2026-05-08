import MuxyShared
import SwiftUI

struct JjFileRow: View {
    let entry: JjStatusEntry
    let onOpenInEditor: () -> Void
    let onOpenDiff: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.change.rawValue)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(statusColor)
                .frame(width: 12)

            Text(entry.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MuxyTheme.fg)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hovered {
                actionButtons
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .contentShape(Rectangle())
        .background(hovered ? MuxyTheme.surface : Color.clear)
        .onHover { hovered = $0 }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "doc.text", size: 11, accessibilityLabel: "Open in Editor", action: onOpenInEditor)
                .help("Open in Editor")
            IconButton(symbol: "rectangle.split.2x1", size: 11, accessibilityLabel: "Open Diff in New Tab", action: onOpenDiff)
                .help("Open Diff in New Tab")
        }
    }

    private var statusColor: Color {
        switch entry.change {
        case .added,
             .copied: MuxyTheme.diffAddFg
        case .deleted: MuxyTheme.diffRemoveFg
        case .modified,
             .renamed: MuxyTheme.fgMuted
        }
    }
}
