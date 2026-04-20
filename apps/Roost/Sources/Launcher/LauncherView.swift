import SwiftUI

struct LauncherView: View {
    @Binding var form: LauncherForm
    /// All known projects. Rendered into the Target picker so user can
    /// cross-target a session without first clicking the sidebar.
    let projects: [Project]
    let onLaunch: () -> Void

    private static let presets = ["claude", "codex", "shell"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            targetSection
            agentSection
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
        .onChange(of: form.target) { _ in
            form.projectPath = matchingProject()?.path ?? ""
            if !projectSupportsWorkspaces {
                form.useJjWorkspace = false
            }
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Target").font(.headline)
            Picker("", selection: $form.target) {
                Text("Scratch (no project)").tag(Project.ID?.none)
                ForEach(projects) { p in
                    Text(p.name).tag(Project.ID?.some(p.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if let p = matchingProject() {
                Text(p.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("cwd: $HOME")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
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

    private var projectSupportsWorkspaces: Bool {
        matchingProject()?.isJjRepo ?? false
    }

    private func matchingProject() -> Project? {
        guard let id = form.target else { return nil }
        return projects.first(where: { $0.id == id })
    }

    private var hint: String {
        if form.useJjWorkspace {
            return "New jj workspace → \(form.projectPath)/.worktrees/<name>."
        } else if !form.projectPath.isEmpty {
            return "Session cwd will be the project directory."
        } else {
            return "Scratch: Rust resolves the binary; falls back to '$SHELL -l -c <agent>'."
        }
    }
}

/// Form state shared between RootView (owner) and launcher UIs.
struct LauncherForm: Equatable {
    var agent: String = "claude"
    /// Destination bucket. `nil` → Scratch. Non-nil → existing project.
    var target: Project.ID? = nil
    /// Mirror of the target project's path for the Rust side (and the
    /// jj-workspace derivation). Kept in sync from `target` by LauncherView.
    var projectPath: String = ""
    var useJjWorkspace: Bool = false
    var workspaceName: String = ""
}
