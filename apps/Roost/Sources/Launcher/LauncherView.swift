import SwiftUI

struct LauncherView: View {
    @Binding var form: LauncherForm
    let onLaunch: () -> Void

    private static let presets = ["claude", "codex", "shell"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            agentSection
            projectSection
            jjSection
            HStack {
                Text(hint)
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

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent").font(.headline)

            HStack(spacing: 8) {
                ForEach(Self.presets, id: \.self) { name in
                    Button(name) { form.agent = name }
                        .buttonStyle(.bordered)
                        .tint(form.agent == name ? .accentColor : .secondary)
                }
            }

            TextField("custom agent name", text: $form.agent, onCommit: onLaunch)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
        }
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Project directory").font(.headline)
            HStack(spacing: 6) {
                TextField("/path/to/repo", text: $form.projectPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                Button("Choose…") { pickDirectory() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var jjSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Run in new jj workspace", isOn: $form.useJjWorkspace)
                .disabled(form.projectPath.isEmpty)
                .help(form.projectPath.isEmpty ? "Pick a project directory first" : "")

            if form.useJjWorkspace {
                TextField(
                    "workspace name (blank = auto)",
                    text: $form.workspaceName
                )
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            }
        }
    }

    private var hint: String {
        if form.useJjWorkspace {
            return "New jj workspace → \(form.projectPath)/.worktrees/<name>."
        } else if !form.projectPath.isEmpty {
            return "Session cwd will be the project directory."
        } else {
            return "Rust resolves the binary; falls back to 'zsh -il -c <agent>'."
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: form.projectPath.isEmpty
            ? NSHomeDirectory()
            : form.projectPath
        )
        if panel.runModal() == .OK, let url = panel.url {
            form.projectPath = url.path
        }
    }
}

/// Form state shared between RootView (owner) and launcher UIs.
struct LauncherForm: Equatable {
    var agent: String = "claude"
    var projectPath: String = ""
    var useJjWorkspace: Bool = false
    var workspaceName: String = ""
}
