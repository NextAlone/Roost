import SwiftUI

struct LauncherView: View {
    @Binding var form: LauncherForm
    /// Whether the currently-selected project is a jj repo. Controls the
    /// availability of the "new jj workspace" toggle.
    let projectSupportsWorkspaces: Bool
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
        .onChange(of: projectSupportsWorkspaces) { supports in
            if !supports {
                form.useJjWorkspace = false
            }
        }
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
                    .disabled(true)
                    .help("Pick the project from the sidebar")
            }
        }
    }

    private var jjSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Run in new jj workspace", isOn: $form.useJjWorkspace)
                .disabled(!projectSupportsWorkspaces)
                .help(
                    projectSupportsWorkspaces
                        ? ""
                        : "Only available for projects inside a jj repository."
                )

            if form.useJjWorkspace && projectSupportsWorkspaces {
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
            return "Rust resolves the binary; falls back to '$SHELL -l -c <agent>'."
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
