import SwiftUI

/// Top-level view. Owns the project store, session list, which tab is
/// active, and the launcher form state. Rendered as a `NavigationSplitView`:
/// projects on the left, active project's terminal pane on the right.
struct RootView: View {
    @StateObject private var projects = ProjectStore()
    @State private var selectedProjectID: Project.ID? = Self.loadSavedSelection()
    @State private var form = LauncherForm()
    @State private var sessions: [LaunchedSession] = []
    @State private var selectedSessionID: LaunchedSession.ID?
    @State private var isShowingLauncher: Bool = false
    @State private var launchError: String?
    /// Session IDs that have seen an OSC 9/99/777 notification since they
    /// were last focused. Cleared when the user selects the session.
    @State private var unreadSessions: Set<UUID> = []
    /// Latest setup/teardown hook failure summary per project, shown as a
    /// sidebar warning. Cleared when the user selects the project.
    @State private var projectHookWarnings: [Project.ID: String] = [:]

    var body: some View {
        NavigationSplitView {
            ProjectSidebar(
                store: projects,
                selection: $selectedProjectID,
                sessions: sessions,
                selectedSessionID: $selectedSessionID,
                unreadProjectIDs: projectsWithUnread,
                unreadSessions: unreadSessions,
                scratchHasUnread: scratchHasUnread,
                scratchSessionCount: scratchSessionCount,
                sessionCountByProject: sessionCountByProject,
                hookWarningsByProject: projectHookWarnings,
                onAdd: addProjectFlow,
                onSelectSession: { sid, pid in
                    // Snap bucket before session so filteredSessions recomputes
                    // and the terminal pane makes the session visible.
                    selectedProjectID = pid ?? Project.scratchID
                    selectedSessionID = sid
                },
                onCloseSession: closeSession
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            detail
        }
        .onChange(of: selectedProjectID) { newID in
            switch newID {
            case nil, Project.scratchID?:
                // Scratch / nothing selected: sessions aren't bound to a
                // directory, so reset the launcher form so ⌘-Launch runs
                // in $HOME rather than the last project's path.
                form.target = nil
                form.projectPath = ""
                form.useJjWorkspace = false
            case let realID?:
                form.target = realID
                if let proj = projects.projects.first(where: { $0.id == realID }) {
                    form.projectPath = proj.path
                }
                projectHookWarnings.removeValue(forKey: realID)
            }
            // When switching bucket, fall back to the first matching session.
            selectedSessionID = filteredSessions.first?.id
            // Persist off-main so rapid bucket switches don't queue up
            // UserDefaults disk writes on the render thread.
            DispatchQueue.global(qos: .utility).async {
                Self.saveSelection(newID)
            }
        }
        .onChange(of: selectedSessionID) { newID in
            if let newID { unreadSessions.remove(newID) }
        }
        .sheet(isPresented: $isShowingLauncher) {
            LauncherSheet(
                form: $form,
                errorMessage: $launchError,
                projects: projects.projects,
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
        .onReceive(NotificationCenter.default.publisher(for: .roostAgentNotification)) { note in
            guard let id = note.userInfo?[RoostNotificationKey.sessionID] as? UUID,
                  id != selectedSessionID
            else { return }
            unreadSessions.insert(id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .roostCloseActiveTab)) { _ in
            if let id = selectedSessionID { closeSession(id: id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .roostSelectTabByIndex)) { note in
            guard let idx = note.userInfo?[RoostNotificationKey.index] as? Int else { return }
            let list = filteredSessions
            guard idx >= 0 && idx < list.count else { return }
            selectedSessionID = list[idx].id
        }
        .onReceive(NotificationCenter.default.publisher(for: .roostSelectRelativeTab)) { note in
            guard let delta = note.userInfo?[RoostNotificationKey.delta] as? Int else { return }
            let list = filteredSessions
            guard !list.isEmpty else { return }
            let currentIdx = list.firstIndex(where: { $0.id == selectedSessionID }) ?? 0
            let next = (currentIdx + delta + list.count) % list.count
            selectedSessionID = list[next].id
        }
        .onReceive(NotificationCenter.default.publisher(for: .roostLaunchAgent)) { note in
            guard let agent = note.userInfo?[RoostNotificationKey.agent] as? String
            else { return }
            openQuickSession(agent: agent)
        }
        .onReceive(NotificationCenter.default.publisher(for: .roostHookProgress)) { note in
            guard let pid = note.userInfo?[RoostNotificationKey.projectID] as? Project.ID,
                  let success = note.userInfo?[RoostNotificationKey.success] as? Bool
            else { return }
            if success {
                return
            }
            let title = note.userInfo?[RoostNotificationKey.title] as? String ?? "hook failed"
            let body = note.userInfo?[RoostNotificationKey.body] as? String ?? ""
            projectHookWarnings[pid] = body.isEmpty ? title : "\(title): \(body)"
        }
    }

    // MARK: - Derived state (notifications)

    /// Set of projects with at least one unread session.
    private var projectsWithUnread: Set<Project.ID> {
        var ids: Set<Project.ID> = []
        for session in sessions where unreadSessions.contains(session.id) {
            if let pid = session.projectID {
                ids.insert(pid)
            }
        }
        return ids
    }

    /// True if any projectID=nil (scratch) session is unread.
    private var scratchHasUnread: Bool {
        sessions.contains { $0.projectID == nil && unreadSessions.contains($0.id) }
    }

    private var scratchSessionCount: Int {
        sessions.lazy.filter { $0.projectID == nil }.count
    }

    private var sessionCountByProject: [Project.ID: Int] {
        var counts: [Project.ID: Int] = [:]
        for session in sessions {
            guard let pid = session.projectID else { continue }
            counts[pid, default: 0] += 1
        }
        return counts
    }

    // MARK: - Derived state

    private var filteredSessions: [LaunchedSession] {
        switch selectedProjectID {
        case nil, Project.scratchID?:
            return sessions.filter { $0.projectID == nil }
        case let pid?:
            return sessions.filter { $0.projectID == pid }
        }
    }

    // MARK: - Detail pane

    /// The detail column. TabBar and overlay (launcher / QuickShell) are
    /// conditional, but `terminalPane` is always in the view tree so the
    /// `TerminalNSView` instances (and their PTYs) survive navigation
    /// between projects with different session sets.
    @ViewBuilder
    private var detail: some View {
        VStack(spacing: 0) {
            if !filteredSessions.isEmpty {
                TabBar(
                    sessions: filteredSessions,
                    selectedID: selectedSessionID,
                    unreadIDs: unreadSessions,
                    onSelect: { selectedSessionID = $0 },
                    onClose: closeSession,
                    onNew: { agent in
                        if let agent = agent {
                            openQuickSession(agent: agent)
                        } else {
                            isShowingLauncher = true
                        }
                    }
                )
                Divider()
            }
            paneArea
        }
    }

    @ViewBuilder
    private var paneArea: some View {
        ZStack {
            terminalPane
            if filteredSessions.isEmpty {
                paneOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var paneOverlay: some View {
        EmptyStateView(
            bucketLabel: emptyBucketLabel,
            onNew: { agent in openQuickSession(agent: agent) }
        )
    }

    private var emptyBucketLabel: String {
        switch selectedProjectID {
        case nil, Project.scratchID?:
            return "Scratch"
        case let id?:
            return projects.projects.first(where: { $0.id == id })?.name ?? "this project"
        }
    }

    /// Renders every session across all projects, exposed via opacity. The
    /// *visible* one is whichever session id equals `selectedSessionID` AND
    /// belongs to the current sidebar bucket — otherwise the pane is blank
    /// but the inactive project's NSViews still exist, preserving their
    /// PTYs when the user navigates away and back.
    @ViewBuilder
    private var terminalPane: some View {
        // Single pass: compute the visible session id once, not per-child
        // (the old code was O(n²) on bucket switches because each child
        //  re-walked `filteredSessions`).
        let visibleID = visibleSessionID
        ZStack {
            ForEach(sessions) { session in
                let visible = session.id == visibleID
                TerminalView(
                    sessionID: session.id,
                    command: session.surfaceCommand,
                    workingDirectory: session.spec.workingDirectory.isEmpty
                        ? nil : session.spec.workingDirectory,
                    attach: session.attach.map { handle in
                        TerminalAttach(
                            attachBinaryPath: handle.attachBinaryPath,
                            backendSessionID: handle.sessionID,
                            socket: handle.socket,
                            authToken: handle.authToken
                        )
                    },
                    isFocused: visible
                )
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
            }
        }
    }

    /// Session id that should be shown right now. `nil` = empty bucket.
    /// O(n) — one pass over `sessions`.
    private var visibleSessionID: UUID? {
        guard let sid = selectedSessionID else { return nil }
        let bucket: Project.ID? =
            (selectedProjectID == Project.scratchID) ? nil : selectedProjectID
        return sessions.first(where: { $0.id == sid && $0.projectID == bucket })?.id
    }

    // MARK: - Projects

    private func addProjectFlow() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Pick a project directory"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path

        // Any directory is fair game; we just record whether it's a jj repo
        // so the launcher knows whether to offer the workspace toggle.
        let isJj = RoostBridge.isJjRepo(dir: path)
        let project = projects.add(path: path, isJjRepo: isJj)
        selectedProjectID = project.id
        form.projectPath = path
    }

    // MARK: - Quick session (⌘T, TabBar one-click buttons)

    /// Spawn a session for `agent` in the current bucket, skipping the
    /// launcher sheet. cwd = selected project's path (or `$HOME` for
    /// Scratch). Used by both ⌘T (agent=shell) and the TabBar one-click
    /// terminal/claude/codex buttons.
    private func openQuickSession(agent: String) {
        let effectiveProjectID: Project.ID? =
            (selectedProjectID == Project.scratchID) ? nil : selectedProjectID
        let cwd: String = effectiveProjectID
            .flatMap { id in projects.projects.first(where: { $0.id == id })?.path }
            ?? ""
        let spec = cwd.isEmpty
            ? RoostBridge.prepareSession(agent: agent)
            : RoostBridge.prepareSession(agent: agent, workingDirectory: cwd)
        let session = LaunchedSession(
            projectID: effectiveProjectID,
            spec: spec,
            label: agent
        )
        sessions.append(session)
        selectedSessionID = session.id
        // Ensure the bucket containing the new session is the active one.
        selectedProjectID = effectiveProjectID ?? Project.scratchID
    }

    // MARK: - Launch

    private func launchFromSheet() {
        NSLog("[Roost] Launch pressed (sheet) agent=%@ target=%@ jj=%d",
              form.agent, form.target?.uuidString ?? "scratch",
              form.useJjWorkspace ? 1 : 0)
        if let s = makeSession() {
            sessions.append(s)
            selectedSessionID = s.id
            // Snap sidebar bucket to the new session's owner so the tab is
            // actually visible.
            selectedProjectID = s.projectID ?? Project.scratchID
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
            // M7: agents (non-shell) go through hostd. Plain shells stay on
            // the M6 path so the terminal launcher keeps working with no
            // hostd round-trip.
            let attach: SessionHandleSwift?
            let agentNorm = spec.agentKind.lowercased()
            if !agentNorm.isEmpty, !["shell", "bash", "zsh", "fish"].contains(agentNorm) {
                attach = try RoostBridge.createSession(
                    agentKind: spec.agentKind,
                    workingDirectory: cwd
                )
                NSLog("[Roost] hostd session sid=%@ via=%@",
                      attach!.sessionID, attach!.attachBinaryPath)
            } else {
                attach = nil
            }
            return LaunchedSession(
                projectID: form.target,
                spec: spec,
                attach: attach,
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

        // M5: run .roost/config.json setup hooks inside the fresh workspace.
        // Non-blocking: hook failures surface as a sidebar warning only, so
        // the caller still gets the session launched.
        if let pid = realProjectID() {
            runHooksAsync(
                phase: "setup",
                projectID: pid,
                projectRoot: project,
                workspaceDir: wsPath
            )
        }

        return (wsPath, "\(form.agent)@\(wsName)")
    }

    /// Launcher form's chosen target, filtered for hook purposes.
    /// Scratch (`target == nil`) has no `.roost/config.json` root.
    private func realProjectID() -> Project.ID? {
        form.target
    }

    /// Run setup/teardown hooks on a background queue and post a
    /// `.roostHookProgress` notification per step back on the main queue.
    /// Hook failures do NOT raise alerts or block the workspace operation;
    /// they show up as sidebar warnings.
    private func runHooksAsync(
        phase: String,
        projectID: Project.ID,
        projectRoot: String,
        workspaceDir: String
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let results: [HookStepResult]
            do {
                switch phase {
                case "teardown":
                    results = try RoostBridge.runTeardownHooks(
                        projectRoot: projectRoot,
                        workspaceDir: workspaceDir
                    )
                default:
                    results = try RoostBridge.runSetupHooks(
                        projectRoot: projectRoot,
                        workspaceDir: workspaceDir
                    )
                }
            } catch let err as RustString {
                let msg = err.toString()
                NSLog("[Roost] %@ hook config error: %@", phase, msg)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .roostHookProgress,
                        object: nil,
                        userInfo: [
                            RoostNotificationKey.projectID: projectID,
                            RoostNotificationKey.phase: phase,
                            RoostNotificationKey.index: 0,
                            RoostNotificationKey.total: 0,
                            RoostNotificationKey.success: false,
                            RoostNotificationKey.title: "\(phase) config",
                            RoostNotificationKey.body: msg,
                        ]
                    )
                }
                return
            } catch {
                NSLog("[Roost] %@ hook failed: %@", phase, String(describing: error))
                return
            }

            for r in results {
                let step = "\(r.index)/\(r.total)"
                let title = r.succeeded
                    ? "\(phase) \(step): \(r.command)"
                    : "\(phase) \(step) failed (exit=\(r.exitCode)): \(r.command)"
                let body = r.stderrTail
                NSLog("[Roost] hook %@ step %@ cmd=%@ exit=%d",
                      phase, step, r.command, r.exitCode)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .roostHookProgress,
                        object: nil,
                        userInfo: [
                            RoostNotificationKey.projectID: projectID,
                            RoostNotificationKey.phase: phase,
                            RoostNotificationKey.index: r.index,
                            RoostNotificationKey.total: r.total,
                            RoostNotificationKey.success: r.succeeded,
                            RoostNotificationKey.title: title,
                            RoostNotificationKey.body: body,
                        ]
                    )
                }
            }
        }
    }

    private func defaultWorkspaceName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd-HHmm"
        return "\(form.agent)-\(formatter.string(from: Date()))"
    }

    // MARK: - Workspace delete (teardown + forget)

    /// Run `.roost/config.json` teardown hooks, then `jj workspace forget`.
    /// Teardown is best-effort: its failures are surfaced as sidebar
    /// warnings and never block the forget. Exposed for future delete-
    /// workspace UI (context menu / sidebar action). Safe to call with
    /// `projectID == nil` (scratch); hooks are skipped in that case.
    func deleteWorkspaceFlow(
        projectID: Project.ID?,
        projectRoot: String,
        workspaceDir: String,
        workspaceName: String
    ) {
        if let pid = projectID {
            // Teardown runs synchronously here (on the main queue) so its
            // post-step notifications land before forget is reported. The
            // whole chain should be dispatched off-main by the caller if
            // it wants no UI hitch.
            runHooksAsync(
                phase: "teardown",
                projectID: pid,
                projectRoot: projectRoot,
                workspaceDir: workspaceDir
            )
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try RoostBridge.forgetWorkspace(
                    repoDir: projectRoot,
                    name: workspaceName
                )
            } catch let err as RustString {
                NSLog("[Roost] forgetWorkspace failed: %@", err.toString())
            } catch {
                NSLog("[Roost] forgetWorkspace failed: %@", String(describing: error))
            }
        }
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

// MARK: - Selection persistence

extension RootView {
    fileprivate static let selectionDefaultsKey = "sh.roost.app.selectedProject"

    fileprivate static func loadSavedSelection() -> Project.ID? {
        guard let raw = UserDefaults.standard.string(forKey: selectionDefaultsKey) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    fileprivate static func saveSelection(_ id: Project.ID?) {
        let defaults = UserDefaults.standard
        if let id {
            defaults.set(id.uuidString, forKey: selectionDefaultsKey)
        } else {
            defaults.removeObject(forKey: selectionDefaultsKey)
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
    /// Set when the agent runs inside hostd (M7+). When non-nil, the surface
    /// child becomes `roost-attach <session_id>` and PTY ownership lives in
    /// the daemon. nil = legacy direct-spawn path.
    let attach: SessionHandleSwift?
    /// Short label shown in the tab (e.g. `claude@ws-foo`). Falls back to
    /// `spec.agentKind` for non-workspace sessions.
    let label: String

    init(
        id: UUID = UUID(),
        projectID: Project.ID? = nil,
        spec: SessionSpecSwift,
        attach: SessionHandleSwift? = nil,
        label: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.spec = spec
        self.attach = attach
        self.label = label ?? spec.agentKind
    }

    /// What ghostty's surface child should run. M7 attach: relay binary +
    /// session id. Legacy: the prepared shell command (or nil for login
    /// shell).
    ///
    /// ghostty parses this string with whitespace splitting; quote the path
    /// so installations under e.g. `/Applications/My Apps/Roost.app/...`
    /// don't break execve. The session id is a UUID and never needs quoting.
    var surfaceCommand: String? {
        if let attach {
            let quoted = Self.shellQuote(attach.attachBinaryPath)
            return "\(quoted) \(attach.sessionID)"
        }
        return spec.command.isEmpty ? nil : spec.command
    }

    private static func shellQuote(_ path: String) -> String {
        // Single-quote shell-style: the only thing a single-quoted POSIX
        // string can't contain is another `'`, which we close-quote, escape,
        // and re-open. Adequate for ghostty's command parser.
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
