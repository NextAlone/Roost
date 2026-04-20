import SwiftUI

/// Top-level view. Owns the project store, session list, which tab is
/// active, and the launcher form state. Rendered as a `NavigationSplitView`:
/// projects on the left, active project's terminal pane on the right.
struct RootView: View {
    @StateObject private var projects = ProjectStore()
    @State private var selectedProjectID: Project.ID?
    @State private var form = LauncherForm()
    @State private var sessions: [LaunchedSession] = []
    @State private var selectedSessionID: LaunchedSession.ID?
    @State private var isShowingLauncher: Bool = false
    @State private var launchError: String?

    private let ghosttyInfo = GhosttyInfo.current
    private let bridgeVersion = RoostBridge.version

    var body: some View {
        NavigationSplitView {
            ProjectSidebar(
                store: projects,
                selection: $selectedProjectID,
                onAdd: addProjectFlow
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            VStack(spacing: 0) {
                HeaderBar(
                    ghosttyInfo: ghosttyInfo,
                    bridgeVersion: bridgeVersion,
                    sessionCount: filteredSessions.count
                )
                Divider()
                detail
            }
        }
        .onChange(of: selectedProjectID) { newID in
            if let newID, let proj = projects.projects.first(where: { $0.id == newID }) {
                form.projectPath = proj.path
            }
            // When switching project, fall back to the first matching session.
            selectedSessionID = filteredSessions.first?.id
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
        .onReceive(NotificationCenter.default.publisher(for: .roostSurfaceClosed)) { note in
            guard let id = note.userInfo?[RoostNotificationKey.sessionID] as? UUID else {
                return
            }
            closeSession(id: id)
        }
    }

    // MARK: - Derived state

    private var filteredSessions: [LaunchedSession] {
        guard let projectID = selectedProjectID else { return sessions }
        return sessions.filter { $0.projectID == projectID }
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detail: some View {
        if filteredSessions.isEmpty {
            LauncherView(form: $form, onLaunch: launchDirect)
        } else {
            VStack(spacing: 0) {
                TabBar(
                    sessions: filteredSessions,
                    selectedID: selectedSessionID,
                    onSelect: { selectedSessionID = $0 },
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
    /// We render *all* sessions (across projects) so switching projects
    /// doesn't tear down the inactive project's terminals either.
    @ViewBuilder
    private var terminalPane: some View {
        ZStack {
            ForEach(sessions) { session in
                TerminalView(
                    sessionID: session.id,
                    command: session.spec.command.isEmpty ? nil : session.spec.command,
                    workingDirectory: session.spec.workingDirectory.isEmpty
                        ? nil : session.spec.workingDirectory
                )
                .opacity(session.id == selectedSessionID ? 1 : 0)
                .allowsHitTesting(session.id == selectedSessionID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Projects

    private func addProjectFlow() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Pick a jj repository"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path

        guard RoostBridge.isJjRepo(dir: path) else {
            launchError = "\(path) is not inside a jj repository. Run `jj init` first."
            return
        }

        let project = projects.add(path: path)
        selectedProjectID = project.id
        form.projectPath = path
    }

    // MARK: - Launch

    private func launchDirect() {
        if let s = makeSession() {
            sessions.append(s)
            selectedSessionID = s.id
        }
    }

    private func launchFromSheet() {
        if let s = makeSession() {
            sessions.append(s)
            selectedSessionID = s.id
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
            return LaunchedSession(
                projectID: selectedProjectID,
                spec: spec,
                label: label
            )
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

    /// Returns (working directory, tab label). Creates the jj workspace if
    /// the form requests it.
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

    // MARK: - Close

    private func closeSession(id: LaunchedSession.ID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: idx)

        if selectedSessionID == id {
            selectedSessionID = filteredSessions.first?.id
        }
    }
}

private enum LaunchError: LocalizedError {
    case missingProject
    var errorDescription: String? {
        switch self {
        case .missingProject:
            "Pick a project directory before creating a jj workspace."
        }
    }
}

/// One active session in the UI.
struct LaunchedSession: Identifiable, Equatable {
    let id: UUID
    /// Project the session belongs to. `nil` = freeform session outside of
    /// any registered project.
    let projectID: Project.ID?
    let spec: SessionSpecSwift
    /// Short label shown in the tab (e.g. `claude@ws-foo`). Falls back to
    /// `spec.agentKind` for non-workspace sessions.
    let label: String

    init(
        id: UUID = UUID(),
        projectID: Project.ID? = nil,
        spec: SessionSpecSwift,
        label: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.spec = spec
        self.label = label ?? spec.agentKind
    }
}
