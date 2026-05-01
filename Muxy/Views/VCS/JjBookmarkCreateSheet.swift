import SwiftUI

struct JjBookmarkCreateSheet: View {
    let title: String
    let confirmLabel: String
    let placeholder: String
    let targetLabel: String?
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String

    init(
        title: String = "New Bookmark",
        confirmLabel: String = "Create",
        placeholder: String = "feature-x",
        initialName: String = "",
        targetLabel: String? = "Target: current change (@)",
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.confirmLabel = confirmLabel
        self.placeholder = placeholder
        self.targetLabel = targetLabel
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 11)).foregroundStyle(MuxyTheme.fgMuted)
                TextField(placeholder, text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            if let targetLabel {
                Text(targetLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmLabel) {
                    onConfirm(name.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
