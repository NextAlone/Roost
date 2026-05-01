import SwiftUI

struct JjConflictContentSheet: View {
    let content: JjConflictContent
    let onOpenInEditor: () -> Void
    let onClose: () -> Void

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

            ScrollView([.vertical, .horizontal]) {
                Text(content.text.isEmpty ? "(empty file)" : content.text)
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
}
