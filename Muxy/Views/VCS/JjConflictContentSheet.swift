import SwiftUI

struct JjConflictContentSheet: View {
    let content: JjConflictContent
    let onOpenInEditor: () -> Void
    let onClose: () -> Void

    private var markerPreview: JjConflictMarkerPreview {
        JjConflictMarkerParser.parse(content.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(MuxyTheme.diffRemoveFg)
                Text(content.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            if markerPreview.regions.isEmpty {
                rawContentView(content.text)
            } else {
                structuredContentView(markerPreview)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Open in Editor", action: onOpenInEditor)
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 760, height: 540)
    }

    private func structuredContentView(_ preview: JjConflictMarkerPreview) -> some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(preview.regions) { region in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Conflict \(region.index)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MuxyTheme.fg)
                        HStack(alignment: .top, spacing: 8) {
                            conflictColumn(title: "Current", text: region.current, tint: MuxyTheme.diffAddFg)
                            conflictColumn(title: "Base", text: region.base, tint: MuxyTheme.fgMuted)
                            conflictColumn(title: "Incoming", text: region.incoming, tint: MuxyTheme.diffRemoveFg)
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(MuxyTheme.border, lineWidth: 1)
        )
    }

    private func conflictColumn(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(text.isEmpty ? "(empty)" : text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MuxyTheme.fg)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(8)
        .frame(width: 220, alignment: .topLeading)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(MuxyTheme.border, lineWidth: 1)
        )
    }

    private func rawContentView(_ text: String) -> some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text.isEmpty ? "(empty file)" : text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MuxyTheme.fg)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(MuxyTheme.border, lineWidth: 1)
        )
    }
}
