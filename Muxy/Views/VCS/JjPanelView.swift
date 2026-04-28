import MuxyShared
import SwiftUI

struct JjPanelView: View {
    @Bindable var state: JjPanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let snapshot = state.snapshot {
                changeCard(snapshot: snapshot)
                Divider()
                fileList(entries: snapshot.parentDiff)
                if snapshot.status.hasConflicts {
                    conflictBanner
                }
            } else if let error = state.errorMessage {
                errorBanner(message: error)
            } else if state.isLoading {
                loadingBanner
            } else {
                emptyState
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await state.refresh() }
    }

    private var header: some View {
        HStack {
            Text("Changes")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(state.isLoading)
            .accessibilityLabel("Refresh")
        }
    }

    private func changeCard(snapshot: JjPanelSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(snapshot.show.change.prefix)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MuxyTheme.accent)
                Text(snapshot.show.change.full)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(snapshot.show.description.isEmpty ? "(no description)" : snapshot.show.description)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    private func fileList(entries: [JjStatusEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Files")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
                Text("(\(entries.count))")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
            }
            if entries.isEmpty {
                Text("No changes vs parent")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgDim)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entries, id: \.path) { entry in
                        HStack(spacing: 6) {
                            Text(entry.change.rawValue)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(color(for: entry.change))
                                .frame(width: 12)
                            Text(entry.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MuxyTheme.fg)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func color(for change: JjFileChange) -> Color {
        switch change {
        case .added, .copied: MuxyTheme.diffAddFg
        case .deleted: MuxyTheme.diffRemoveFg
        case .modified, .renamed: MuxyTheme.fgMuted
        }
    }

    private var conflictBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MuxyTheme.diffRemoveFg)
            Text("This change has conflicts")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MuxyTheme.diffRemoveFg)
            Spacer()
        }
        .padding(8)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(MuxyTheme.diffRemoveFg)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.diffRemoveFg)
            Spacer()
        }
        .padding(10)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    private var loadingBanner: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Loading…")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
        }
    }

    private var emptyState: some View {
        Text("No data")
            .font(.system(size: 11))
            .foregroundStyle(MuxyTheme.fgDim)
    }
}
