import SwiftUI

struct JjConflictContentSheet: View {
    let content: JjConflictContent
    let onOpenInEditor: () -> Void
    let onSaveResolvedContent: (String) -> Void
    let onClose: () -> Void
    private let markerPreview: JjConflictMarkerPreview

    @State private var resolutionDrafts: [Int: String]

    init(
        content: JjConflictContent,
        onOpenInEditor: @escaping () -> Void,
        onSaveResolvedContent: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.content = content
        self.onOpenInEditor = onOpenInEditor
        self.onSaveResolvedContent = onSaveResolvedContent
        self.onClose = onClose
        let preview = JjConflictMarkerParser.parse(content.text)
        self.markerPreview = preview
        _resolutionDrafts = State(
            initialValue: Dictionary(uniqueKeysWithValues: preview.regions.map { ($0.index, $0.current) })
        )
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
                if !markerPreview.regions.isEmpty {
                    Button("Save Resolved") {
                        onSaveResolvedContent(markerPreview.resolvedText(replacements: resolutionDrafts))
                    }
                    .keyboardShortcut(.defaultAction)
                }
                Button("Done", action: onClose)
                    .keyboardShortcut(markerPreview.regions.isEmpty ? .defaultAction : nil)
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
                        conflictResolutionEditor(region)
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

    private func conflictResolutionEditor(_ region: JjConflictMarkerRegion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Resolved")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MuxyTheme.accent)
            TextEditor(text: binding(for: region))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(MuxyTheme.fg)
                .scrollContentBackground(.hidden)
                .frame(width: 676, height: 120)
                .padding(4)
                .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(MuxyTheme.border, lineWidth: 1)
                )
        }
    }

    private func binding(for region: JjConflictMarkerRegion) -> Binding<String> {
        Binding(
            get: { resolutionDrafts[region.index] ?? region.current },
            set: { resolutionDrafts[region.index] = $0 }
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
