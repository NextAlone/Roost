import MuxyShared
import SwiftUI

struct JjActionBar: View {
    let onDescribe: () -> Void
    let onNew: () -> Void
    let onCommit: () -> Void
    let onSquash: () -> Void
    let onAbandon: () -> Void
    let onDuplicate: () -> Void
    let onBackout: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            actionButton(systemImage: "pencil", label: "Describe", action: onDescribe)
            actionButton(systemImage: "plus.circle", label: "New", action: onNew)
            actionButton(systemImage: "checkmark.circle", label: "Commit", action: onCommit)
            actionButton(systemImage: "arrow.down.to.line", label: "Squash", action: onSquash)
            Divider().frame(height: 16)
            actionButton(systemImage: "trash", label: "Abandon", action: onAbandon)
            actionButton(systemImage: "doc.on.doc", label: "Duplicate", action: onDuplicate)
            actionButton(systemImage: "arrow.uturn.backward", label: "Backout", action: onBackout)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    private func actionButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
        .buttonStyle(.borderless)
        .help(label)
    }
}
