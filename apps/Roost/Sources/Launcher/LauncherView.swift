import SwiftUI

struct LauncherView: View {
    @Binding var agentDraft: String
    let onLaunch: () -> Void

    private static let presets = ["claude", "codex", "shell"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Agent")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(Self.presets, id: \.self) { name in
                    Button(name) { agentDraft = name }
                        .buttonStyle(.bordered)
                        .tint(agentDraft == name ? .accentColor : .secondary)
                }
            }

            TextField("custom agent name", text: $agentDraft, onCommit: onLaunch)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())

            HStack {
                Text("Rust resolves the binary path; falls back to 'zsh -il -c <agent>'.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Launch", action: onLaunch)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
