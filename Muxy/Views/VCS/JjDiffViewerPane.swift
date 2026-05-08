import SwiftUI

struct JjDiffViewerPane: View {
    @Bindable var state: JjDiffViewerTabState
    let focused: Bool
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            JjDiffViewerBreadcrumb(state: state)
            Rectangle().fill(MuxyTheme.border).frame(height: 1)
            ScrollView([.vertical]) {
                DiffBodyView(
                    isLoading: state.diffCache.isLoading(state.filePath),
                    error: state.diffCache.error(for: state.filePath),
                    diff: state.diffCache.diff(for: state.filePath),
                    filePath: state.filePath,
                    mode: state.mode,
                    onLoadFull: { state.refresh(forceFull: true) },
                    suppressLeadingTopBorder: true
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(MuxyTheme.bg)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
    }
}

private struct JjDiffViewerBreadcrumb: View {
    @Bindable var state: JjDiffViewerTabState

    private var loadedDiff: DiffCache.LoadedDiff? {
        state.diffCache.diff(for: state.filePath)
    }

    var body: some View {
        HStack(spacing: 6) {
            FileDiffIcon()
                .stroke(MuxyTheme.fgDim, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 11, height: 11)

            Text(state.filePath)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if let diff = loadedDiff {
                if diff.additions > 0 {
                    Text("+\(diff.additions)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MuxyTheme.diffAddFg)
                }
                if diff.deletions > 0 {
                    Text("-\(diff.deletions)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MuxyTheme.diffRemoveFg)
                }
            }

            Spacer()

            modeToggle

            IconButton(symbol: "arrow.clockwise", size: 11, accessibilityLabel: "Refresh Diff") {
                state.refresh(forceFull: false)
            }
            .help("Refresh")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(MuxyTheme.bg)
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(.split, symbol: "rectangle.split.2x1", tooltip: "Side by side")
            modeButton(.unified, symbol: "rectangle", tooltip: "Inline")
        }
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(MuxyTheme.border, lineWidth: 1))
    }

    private func modeButton(_ mode: VCSTabState.ViewMode, symbol: String, tooltip: String) -> some View {
        let selected = state.mode == mode
        return Button {
            state.mode = mode
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? MuxyTheme.fg : MuxyTheme.fgMuted)
                .frame(width: 22, height: 20)
                .background(selected ? MuxyTheme.bg : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
