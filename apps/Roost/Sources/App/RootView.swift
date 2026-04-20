import SwiftUI

/// Top-level view. Owns the session list, which tab is active, and the
/// launcher form state.
struct RootView: View {
    @State private var form = LauncherForm()
    @State private var sessions: [LaunchedSession] = []
    @State private var selectedID: LaunchedSession.ID?
    @State private var isShowingLauncher: Bool = false
    @State private var launchError: String?

    private let ghosttyInfo = GhosttyInfo.current
    private let bridgeVersion = RoostBridge.version

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                ghosttyInfo: ghosttyInfo,
                bridgeVersion: bridgeVersion,
                sessionCount: sessions.count
            )
            Divider()
            content
        }
        .sheet(isPresented: $isShowingLauncher) {
            LauncherSheet(
                form: $form,
                errorMessage: $launchError,
                onLaunch: { launchFromSheet() },
                onCancel: { isShowingLauncher = false }
            )
        }
        .alert(
            "Launch failed",
            isPresented: Binding(
                get: { launchError != nil },
                set: { if !$0 { launchError = nil } }
            ),
            presenting: launchError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        if sessions.isEmpty {
            LauncherView(form: $form, onLaunch: launchDirect)
        } else {
            VStack(spacing: 0) {
                TabBar(
                    sessions: sessions,
                    selectedID: selectedID,
                    onSelect: { selectedID = $0 },
                    onClose: closeSession,
                    onNew: { isShowingLauncher = true }
                )
                Divider()
                terminalPane
            }
        }
    }

    /// Keep every session's `TerminalNSView` alive for the lifetime of the
    /// session; switching tabs only flips visibility. Using `.id(selectedID)`
    /// here (single view) would rebuild the NSView and kill the child PTY.
    @ViewBuilder
    private var terminalPane: some View {
        ZStack {
            ForEach(sessions) { session in
                TerminalView(
                    command: session.spec.command.isEmpty ? nil : session.spec.command,
                    workingDirectory: session.spec.workingDirectory.isEmpty
                        ? nil : session.spec.workingDirectory
                )
                .opacity(session.id == selectedID ? 1 : 0)
                .allowsHitTesting(session.id == selectedID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Launch

    private func launchDirect() {
        if let s = makeSession() {
            sessions.append(s)
            selectedID = s.id
        }
    }

    private func launchFromSheet() {
        if let s = makeSession() {
            sessions.append(s)
            selectedID = s.id
            isShowingLauncher = false
        }
    }

    private func makeSession() -> LaunchedSession? {
        do {
            let (cwd, label) = try resolveCwd()
            let spec = cwd.isEmpty
                ? RoostBridge.prepareSession(agent: form.agent)
                : RoostBridge.prepareSession(agent: form.agent, workingDirectory: cwd)
            NSLog("[Roost] launch: agent=%@ cwd=%@ cmd=%@", form.agent, cwd, spec.command)
            return LaunchedSession(spec: spec, label: label)
        } catch let err as RustString {
            let msg = err.toString()
            NSLog("[Roost] launch failed (rust): %@", msg)
            launchError = msg
            return nil
        } catch {
            let msg = String(describing: error)
            NSLog("[Roost] launch failed: %@", msg)
            launchError = msg
            return nil
        }
    }

    /// Returns (working directory, tab label). Creates the jj workspace if the
    /// form requests it.
    private func resolveCwd() throws -> (String, String) {
        let project = form.projectPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard form.useJjWorkspace else {
            return (project, form.agent)
        }
        guard !project.isEmpty else {
            throw LaunchError.missingProject
        }

        let name = form.workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let wsName = name.isEmpty ? defaultWorkspaceName() : name
        let wsPath = "\(project)/.worktrees/\(wsName)"

        _ = try RoostBridge.addWorkspace(
            repoDir: project,
            workspacePath: wsPath,
            name: wsName
        )
        return (wsPath, "\(form.agent)@\(wsName)")
    }

    private func defaultWorkspaceName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd-HHmm"
        return "\(form.agent)-\(formatter.string(from: Date()))"
    }

    // MARK: Close

    private func closeSession(id: LaunchedSession.ID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: idx)
        guard !sessions.isEmpty else { selectedID = nil; return }
        if selectedID == id {
            selectedID = sessions[min(idx, sessions.count - 1)].id
        }
    }
}

private enum LaunchError: LocalizedError {
    case missingProject
    var errorDescription: String? {
        switch self {
        case .missingProject: "Pick a project directory before creating a jj workspace."
        }
    }
}

/// One active session in the UI.
struct LaunchedSession: Identifiable, Equatable {
    let id: UUID
    let spec: SessionSpecSwift
    /// Short label shown in the tab (e.g. `claude@ws-foo`). Falls back to
    /// `spec.agentKind` for non-workspace sessions.
    let label: String

    init(id: UUID = UUID(), spec: SessionSpecSwift, label: String? = nil) {
        self.id = id
        self.spec = spec
        self.label = label ?? spec.agentKind
    }
}
