import AppKit
import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @Environment(WorkspaceStatusStore.self) private var statusStore
    @Environment(GhosttyService.self) private var ghostty
    @Environment(\.roostHostdClient) private var hostdClient
    @Environment(\.openWindow) private var openWindow
    @State private var dragCoordinator = TabDragCoordinator()
    private enum AttachedVCSLayout {
        static let minWidth: CGFloat = 200
        static let defaultWidth: CGFloat = 400
        static let maxWidth: CGFloat = 800
    }

    private enum FileTreeLayout {
        static let minWidth: CGFloat = 180
        static let defaultWidth: CGFloat = 260
        static let maxWidth: CGFloat = 600
    }

    private enum CloseConfirmationKind {
        case unsavedEditor
        case runningProcess

        var title: String {
            switch self {
            case .unsavedEditor:
                "Save Changes Before Closing?"
            case .runningProcess:
                "Close Tab?"
            }
        }

        var message: String {
            switch self {
            case .unsavedEditor:
                "This file has unsaved changes. If you don't save, your changes will be lost."
            case .runningProcess:
                "A process is still running in this tab. Are you sure you want to close it?"
            }
        }
    }

    private struct MountedTerminalWorktree: Identifiable {
        let key: WorktreeKey
        let project: Project

        var id: WorktreeKey { key }
    }

    @State private var vcsPanelVisible = false
    @State private var vcsPanelWidth: CGFloat = AttachedVCSLayout.defaultWidth
    @State private var vcsStates: [WorktreeKey: VCSTabState] = [:]
    @State private var sidePanelStateSyncTask: Task<Void, Never>?
    @State private var fileTreePanelVisible = false
    @AppStorage("muxy.fileTreeWidth") private var fileTreePanelWidth: Double = .init(FileTreeLayout.defaultWidth)
    @State private var fileTreeStates: [WorktreeKey: FileTreeState] = [:]
    @State private var mountedTerminalWorktreeKeys: Set<WorktreeKey> = []
    @State private var showQuickOpen = false
    @State private var showFindInFiles = false
    @State private var showWorktreeSwitcher = false
    @State private var isFullScreen = false
    @State private var sidebarExpanded = UserDefaults.standard.bool(forKey: "muxy.sidebarExpanded")
    @AppStorage(SidebarCollapsedStyle.storageKey) private var sidebarCollapsedStyleRaw = SidebarCollapsedStyle.defaultValue.rawValue
    @AppStorage(SidebarExpandedStyle.storageKey) private var sidebarExpandedStyleRaw = SidebarExpandedStyle.defaultValue.rawValue
    @AppStorage("muxy.notifications.toastPosition") private var toastPositionRaw = ToastPosition.topCenter.rawValue
    private let trafficLightWidth: CGFloat = 75

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if !isFullScreen {
                    Color.clear
                        .frame(width: topBarLeadingWidth)
                        .fixedSize(horizontal: true, vertical: false)
                        .overlay(alignment: .trailing) {
                            HStack(spacing: 0) {
                                navigationArrows
                                Rectangle().fill(MuxyTheme.border).frame(width: 1)
                            }
                        }
                }
                topBarContent
            }
            .frame(height: 32)
            .background(WindowDragRepresentable())
            .background(MuxyTheme.bg)

            Rectangle().fill(MuxyTheme.border).frame(height: 1)
                .background(MuxyTheme.bg)

            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    Sidebar()
                    if !SidebarLayout.isHidden(expanded: sidebarExpanded, collapsedStyle: sidebarCollapsedStyle) {
                        Rectangle().fill(MuxyTheme.border).frame(width: 1)
                            .accessibilityHidden(true)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .background(MuxyTheme.bg)

                ZStack {
                    MuxyTheme.bg
                    if let project = activeProject,
                       appState.workspaceRoot(for: project.id) == nil
                    {
                        StartupView(project: project, worktree: resolvedActiveWorktree(for: project))
                    } else if projectsWithWorkspaces.isEmpty {
                        StartupView(project: nil, worktree: nil)
                    } else {
                        let activeKey = activeWorktreeKey
                        ForEach(mountedTerminalWorktrees) { item in
                            let key = item.key
                            let project = item.project
                            let isActive = key == activeKey
                            TerminalArea(
                                project: project,
                                worktreeKey: key,
                                isActiveProject: isActive
                            )
                            .opacity(isActive ? 1 : 0)
                            .allowsHitTesting(isActive)
                            .zIndex(isActive ? 1 : 0)
                        }
                    }
                }

                if vcsPanelVisible, VCSDisplayMode.current == .attached {
                    HStack(spacing: 0) {
                        sidePanelResizeHandle { delta in
                            vcsPanelWidth = max(
                                AttachedVCSLayout.minWidth,
                                min(AttachedVCSLayout.maxWidth, vcsPanelWidth - delta)
                            )
                        }
                        if let state = activeVCSState {
                            VCSTabView(state: state, focused: false, onFocus: {})
                                .frame(width: vcsPanelWidth)
                        } else {
                            MuxyTheme.bg.frame(width: vcsPanelWidth)
                        }
                    }
                } else if fileTreePanelVisible {
                    HStack(spacing: 0) {
                        sidePanelResizeHandle { delta in
                            let next = fileTreePanelWidth - Double(delta)
                            fileTreePanelWidth = max(
                                Double(FileTreeLayout.minWidth),
                                min(Double(FileTreeLayout.maxWidth), next)
                            )
                        }
                        if let treeState = activeFileTreeState {
                            FileTreeView(
                                state: treeState,
                                onOpenFile: { filePath in
                                    guard let projectID = appState.activeProjectID else { return }
                                    appState.openFile(filePath, projectID: projectID, preserveFocus: true)
                                },
                                onOpenTerminal: { directory in
                                    guard let projectID = appState.activeProjectID else { return }
                                    appState.dispatch(.createTabInDirectory(
                                        projectID: projectID,
                                        areaID: nil,
                                        directory: directory
                                    ))
                                },
                                onFileMoved: { oldPath, newPath in
                                    appState.handleFileMoved(from: oldPath, to: newPath)
                                }
                            )
                            .id(treeState.rootPath)
                            .frame(width: CGFloat(fileTreePanelWidth))
                        } else {
                            MuxyTheme.bg.frame(width: CGFloat(fileTreePanelWidth))
                        }
                    }
                }
            }
        }
        .environment(\.overlayActive, showQuickOpen || showFindInFiles || showWorktreeSwitcher)
        .overlay(alignment: toastAlignment) {
            if let toast = ToastState.shared.message {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MuxyTheme.diffAddFg)
                    Text(toast)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuxyTheme.fg)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(MuxyTheme.bg, in: Capsule())
                .overlay(Capsule().stroke(MuxyTheme.border, lineWidth: 1))
                .padding(toastEdgePadding)
                .transition(.move(edge: toastTransitionEdge).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityLabel(toast)
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .overlay {
            if showQuickOpen, let project = activeProject {
                QuickOpenOverlay(
                    projectPath: activeWorktreePath(for: project),
                    onSelect: { filePath in
                        showQuickOpen = false
                        appState.openFile(filePath, projectID: project.id)
                    },
                    onDismiss: { showQuickOpen = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .overlay {
            if showFindInFiles, let project = activeProject {
                FindInFilesOverlay(
                    projectPath: activeWorktreePath(for: project),
                    onSelect: { match in
                        showFindInFiles = false
                        appState.openFile(
                            match.absolutePath,
                            projectID: project.id,
                            line: match.lineNumber,
                            column: match.column
                        )
                    },
                    onDismiss: { showFindInFiles = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .overlay {
            if showWorktreeSwitcher {
                WorktreeSwitcherOverlay(
                    items: worktreeSwitcherItems,
                    activeKey: activeWorktreeKey,
                    onSelect: { item in
                        showWorktreeSwitcher = false
                        guard let project = projectStore.projects.first(where: { $0.id == item.projectID }) else { return }
                        if appState.activeProjectID == item.projectID {
                            appState.selectWorktree(projectID: item.projectID, worktree: item.worktree)
                        } else {
                            appState.selectProject(project, worktree: item.worktree)
                        }
                    },
                    onDismiss: { showWorktreeSwitcher = false }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showQuickOpen)
        .animation(.easeInOut(duration: 0.15), value: showFindInFiles)
        .animation(.easeInOut(duration: 0.15), value: showWorktreeSwitcher)
        .animation(.easeInOut(duration: 0.2), value: ToastState.shared.message != nil)
        .coordinateSpace(name: DragCoordinateSpace.mainWindow)
        .environment(dragCoordinator)
        .background(MainWindowShortcutInterceptor(
            onShortcut: { action in handleShortcutAction(action) },
            onCommandShortcut: { shortcut in handleCommandShortcut(shortcut) },
            onMouseBack: { appState.goBack() },
            onMouseForward: { appState.goForward() }
        ))
        .background(WindowConfigurator(configVersion: ghostty.configVersion))
        .background(WindowTitleUpdater(title: windowTitle))
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: .quickOpen)) { _ in
            showQuickOpen.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInFiles)) { _ in
            showFindInFiles.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchWorktree)) { _ in
            showWorktreeSwitcher.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                sidebarExpanded.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .windowFullScreenDidChange)) { notification in
            isFullScreen = notification.userInfo?["isFullScreen"] as? Bool ?? false
        }
        .background(WindowOpenReceiver(openWindow: openWindow))
        .onReceive(NotificationCenter.default.publisher(for: .toggleAttachedVCS)) { _ in
            toggleAttachedVCSPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFileTree)) { _ in
            toggleFileTreePanel()
        }
        .onChange(of: vcsPruneSignature) {
            handleVCSPruneSignatureChange()
        }
        .onChange(of: terminalWorkspaceSignature, initial: true) {
            handleTerminalWorkspaceSignatureChange()
        }
        .onChange(of: activeWorktreeKey, initial: true) { _, key in
            handleActiveWorktreeKeyChange(key)
        }
        .onChange(of: vcsEnsureSignature) {
            handleVCSEnsureSignatureChange()
        }
        .modifier(FileTreeSelectionSync(
            filePath: activeEditorFilePath,
            panelVisible: fileTreePanelVisible,
            sync: syncFileTreeSelection
        ))
        .modifier(AlertObservers(
            appState: appState,
            presentCloseConfirmation: presentCloseConfirmation,
            presentSaveErrorAlert: presentSaveErrorAlert,
            presentLayoutApplyBlockedAlert: presentLayoutApplyBlockedAlert,
            presentLayoutApplyConfirmation: presentLayoutApplyConfirmation
        ))
        .onChange(of: worktreeStore.worktrees, initial: true) { _, current in
            handleWorktreeStoreChange(current)
        }
    }

    private struct AlertObservers: ViewModifier {
        let appState: AppState
        let presentCloseConfirmation: (CloseConfirmationKind) -> Void
        let presentSaveErrorAlert: (String) -> Void
        let presentLayoutApplyBlockedAlert: (String) -> Void
        let presentLayoutApplyConfirmation: (AppState.PendingLayoutApply) -> Void

        func body(content: Content) -> some View {
            content
                .onChange(of: appState.pendingUnsavedEditorTabClose != nil) { _, isPresented in
                    guard isPresented else { return }
                    presentCloseConfirmation(.unsavedEditor)
                }
                .onChange(of: appState.pendingProcessTabClose != nil) { _, isPresented in
                    guard isPresented else { return }
                    presentCloseConfirmation(.runningProcess)
                }
                .onChange(of: appState.pendingSaveErrorMessage != nil) { _, isPresented in
                    guard isPresented, let message = appState.pendingSaveErrorMessage else { return }
                    presentSaveErrorAlert(message)
                }
                .onChange(of: appState.pendingLayoutApplyBlockedMessage != nil) { _, isPresented in
                    guard isPresented, let message = appState.pendingLayoutApplyBlockedMessage else { return }
                    presentLayoutApplyBlockedAlert(message)
                }
                .onChange(of: appState.pendingLayoutApply != nil) { _, isPresented in
                    guard isPresented, let pending = appState.pendingLayoutApply else { return }
                    presentLayoutApplyConfirmation(pending)
                }
        }
    }

    private var navigationArrows: some View {
        HStack(spacing: 2) {
            NavigationArrowButton(
                symbol: "chevron.left",
                isEnabled: appState.navigation.canGoBack,
                label: "Back (\(KeyBindingStore.shared.displayString(for: .navigateBack)))"
            ) {
                appState.goBack()
            }
            NavigationArrowButton(
                symbol: "chevron.right",
                isEnabled: appState.navigation.canGoForward,
                label: "Forward (\(KeyBindingStore.shared.displayString(for: .navigateForward)))"
            ) {
                appState.goForward()
            }
        }
        .padding(.trailing, 4)
    }

    @ViewBuilder
    private var topBarContent: some View {
        if let project = activeProject,
           let root = appState.workspaceRoot(for: project.id),
           case let .tabArea(area) = root
        {
            PaneTabStrip(
                areaID: area.id,
                tabs: PaneTabStrip.snapshots(from: area.tabs),
                activeTabID: area.activeTabID,
                isFocused: true,
                isWindowTitleBar: true,
                showVCSButton: true,
                showDevelopmentBadge: AppEnvironment.isDevelopment,
                openInIDEProjectPath: activeWorktreePath(for: project),
                openInIDEFilePath: area.activeTab?.content.editorState?.filePath,
                openInIDECursorProvider: {
                    guard let editorState = appState.activeTab(for: project.id)?.content.editorState else {
                        return (nil, nil)
                    }
                    return (editorState.cursorLine, editorState.cursorColumn)
                },
                projectID: project.id,
                onSelectTab: { tabID in
                    appState.dispatch(.selectTab(projectID: project.id, areaID: area.id, tabID: tabID))
                },
                onCreateTab: {
                    appState.dispatch(.createTab(projectID: project.id, areaID: area.id))
                },
                onCreateAgentTab: { kind in
                    appState.createAgentTab(kind, projectID: project.id, areaID: area.id, hostdClient: hostdClient)
                },
                onCreateVCSTab: {
                    openVCS(for: project, preferredAreaID: area.id)
                },
                onCloseTab: { tabID in
                    appState.closeTab(tabID, areaID: area.id, projectID: project.id)
                },
                onCloseOtherTabs: { tabID in
                    for id in area.tabs.filter({ $0.id != tabID && !$0.isPinned }).map(\.id) {
                        appState.closeTab(id, areaID: area.id, projectID: project.id)
                    }
                },
                onCloseTabsToLeft: { tabID in
                    guard let index = area.tabs.firstIndex(where: { $0.id == tabID }) else { return }
                    for id in area.tabs.prefix(index).filter({ !$0.isPinned }).map(\.id) {
                        appState.closeTab(id, areaID: area.id, projectID: project.id)
                    }
                },
                onCloseTabsToRight: { tabID in
                    guard let index = area.tabs.firstIndex(where: { $0.id == tabID }) else { return }
                    for id in area.tabs.suffix(from: index + 1).filter({ !$0.isPinned }).map(\.id) {
                        appState.closeTab(id, areaID: area.id, projectID: project.id)
                    }
                },
                onSplit: { dir in
                    appState.dispatch(.splitArea(.init(
                        projectID: project.id,
                        areaID: area.id,
                        direction: dir,
                        position: .second
                    )))
                },
                onDropAction: { result in
                    appState.dispatch(result.action(projectID: project.id))
                },
                onCreateTabAdjacent: { tabID, side in
                    area.createTabAdjacent(to: tabID, side: side)
                },
                onTogglePin: { tabID in
                    area.togglePin(tabID)
                },
                onSetCustomTitle: { tabID, title in
                    area.setCustomTitle(tabID, title: title)
                    appState.saveWorkspaces()
                },
                onSetColorID: { tabID, colorID in
                    area.setColorID(tabID, colorID: colorID)
                    appState.saveWorkspaces()
                },
                onReorderTab: { fromOffsets, toOffset in
                    area.reorderTab(fromOffsets: fromOffsets, toOffset: toOffset)
                }
            )
        } else {
            WindowDragRepresentable(alwaysEnabled: true)
                .overlay {
                    HStack {
                        if let project = activeProject {
                            Text(project.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MuxyTheme.fgMuted)
                                .padding(.leading, 12)
                        }
                        Spacer(minLength: 0)
                    }
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .trailing) {
                    HStack(spacing: 0) {
                        if AppEnvironment.isDevelopment {
                            devModeBadge
                                .padding(.trailing, 6)
                        }
                        if let project = activeProject {
                            OpenInIDEControl(
                                projectPath: activeWorktreePath(for: project),
                                filePath: activeEditorFilePath,
                                cursorProvider: activeEditorCursor
                            )
                            LayoutPickerMenu(projectID: project.id)
                        }
                        if let version = UpdateService.shared.availableUpdateVersion {
                            UpdateBadge(version: version) {
                                UpdateService.shared.checkForUpdates()
                            }
                            .padding(.trailing, 4)
                        }
                        if let project = activeProject, activeProjectHasSplitWorkspace {
                            IconButton(symbol: "doc.text", size: 12, accessibilityLabel: "Quick Open") {
                                NotificationCenter.default.post(name: .quickOpen, object: nil)
                            }
                            .help("Quick Open (\(KeyBindingStore.shared.displayString(for: .quickOpen)))")
                            FileDiffIconButton {
                                openVCS(for: project)
                            }
                            FileTreeIconButton {
                                NotificationCenter.default.post(name: .toggleFileTree, object: nil)
                            }
                            .help("File Tree (\(KeyBindingStore.shared.displayString(for: .toggleFileTree)))")
                        }
                    }
                    .padding(.trailing, 4)
                }
        }
    }

    private var worktreeSwitcherItems: [WorktreeSwitcherItem] {
        projectStore.projects.flatMap { project in
            worktreeStore.list(for: project.id).map { worktree in
                WorktreeSwitcherItem(
                    projectID: project.id,
                    projectName: project.name,
                    worktree: worktree
                )
            }
        }
    }

    private var toastPosition: ToastPosition {
        ToastState.shared.position ?? ToastPosition(rawValue: toastPositionRaw) ?? .topCenter
    }

    private var toastAlignment: Alignment {
        switch toastPosition {
        case .topCenter: .top
        case .topRight: .topTrailing
        case .bottomCenter: .bottom
        case .bottomRight: .bottomTrailing
        }
    }

    private var toastEdgePadding: EdgeInsets {
        switch toastPosition {
        case .topCenter: EdgeInsets(top: 40, leading: 0, bottom: 0, trailing: 0)
        case .topRight: EdgeInsets(top: 40, leading: 0, bottom: 0, trailing: 16)
        case .bottomCenter: EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
        case .bottomRight: EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 16)
        }
    }

    private var toastTransitionEdge: Edge {
        switch toastPosition {
        case .topCenter,
             .topRight: .top
        case .bottomCenter,
             .bottomRight: .bottom
        }
    }

    private var sidebarCollapsedStyle: SidebarCollapsedStyle {
        SidebarCollapsedStyle(rawValue: sidebarCollapsedStyleRaw) ?? .defaultValue
    }

    private var sidebarExpandedStyle: SidebarExpandedStyle {
        SidebarExpandedStyle(rawValue: sidebarExpandedStyleRaw) ?? .defaultValue
    }

    private var topBarLeadingWidth: CGFloat {
        let sidebarWidth = SidebarLayout.resolvedWidth(
            expanded: sidebarExpanded,
            collapsedStyle: sidebarCollapsedStyle,
            expandedStyle: sidebarExpandedStyle
        ) + 1
        let navigationMinimum = trafficLightWidth + navigationArrowsWidth
        return max(navigationMinimum, sidebarWidth)
    }

    private var navigationArrowsWidth: CGFloat { 52 }

    private var devModeBadge: some View {
        DebugButton()
    }

    private var activeWorktreeKey: WorktreeKey? {
        guard let projectID = appState.activeProjectID,
              let worktreeID = appState.activeWorktreeID[projectID]
        else { return nil }
        return WorktreeKey(projectID: projectID, worktreeID: worktreeID)
    }

    private static let scratchProject = Project(id: Project.scratchID, name: "Scratch", path: Worktree.scratchPath)

    private var activeProject: Project? {
        guard let pid = appState.activeProjectID else { return nil }
        if pid == Project.scratchID {
            return Self.scratchProject
        }
        return projectStore.projects.first { $0.id == pid }
    }

    private var windowTitle: String {
        WindowTitleFormatter.title(
            projectName: activeProject?.name,
            tabTitle: activeProject.flatMap { appState.activeTab(for: $0.id)?.title }
        )
    }

    private func resolvedActiveWorktree(for project: Project) -> Worktree? {
        worktreeStore.preferred(for: project.id, matching: appState.activeWorktreeID[project.id])
    }

    private var shortcutDispatcher: ShortcutActionDispatcher {
        ShortcutActionDispatcher(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore,
            ghostty: ghostty
        )
    }

    private var mountedTerminalWorktrees: [MountedTerminalWorktree] {
        var projectByID = Dictionary(uniqueKeysWithValues: projectStore.projects.map { ($0.id, $0) })
        projectByID[Project.scratchID] = Self.scratchProject
        return MountedTerminalWorktreePolicy.displayKeys(
            remembered: mountedTerminalWorktreeKeys,
            active: activeWorktreeKey,
            available: availableTerminalWorktreeKeys,
            agentBearing: agentBearingTerminalWorktreeKeys
        )
        .compactMap { key in
            guard let project = projectByID[key.projectID] else { return nil }
            return MountedTerminalWorktree(key: key, project: project)
        }
    }

    private var availableTerminalWorktreeKeys: Set<WorktreeKey> {
        var projectIDs = Set(projectStore.projects.map(\.id))
        projectIDs.insert(Project.scratchID)
        return Set(appState.workspaceRoots.keys.filter { projectIDs.contains($0.projectID) })
    }

    private var agentBearingTerminalWorktreeKeys: Set<WorktreeKey> {
        Set(appState.workspaceRoots.compactMap { key, root in
            root.allAreas().contains { area in
                area.tabs.contains { tab in
                    guard let agentKind = tab.content.pane?.agentKind else { return false }
                    return agentKind != .terminal
                }
            } ? key : nil
        })
    }

    private func rememberMountedTerminalWorktree(_ key: WorktreeKey?) {
        var remembered = mountedTerminalWorktreeKeys
        MountedTerminalWorktreePolicy.remember(
            active: key,
            available: availableTerminalWorktreeKeys,
            remembered: &remembered
        )
        mountedTerminalWorktreeKeys = remembered
    }

    private func pruneMountedTerminalWorktrees() {
        var remembered = mountedTerminalWorktreeKeys
        MountedTerminalWorktreePolicy.prune(
            available: availableTerminalWorktreeKeys,
            remembered: &remembered
        )
        mountedTerminalWorktreeKeys = remembered
    }

    private func handleVCSPruneSignatureChange() {
        pruneVCSStates()
        pruneFileTreeStates()
    }

    private func handleTerminalWorkspaceSignatureChange() {
        pruneMountedTerminalWorktrees()
        rememberMountedTerminalWorktree(activeWorktreeKey)
    }

    private func handleActiveWorktreeKeyChange(_ key: WorktreeKey?) {
        rememberMountedTerminalWorktree(key)
    }

    private func handleVCSEnsureSignatureChange() {
        scheduleSidePanelStateSync()
    }

    private func handleWorktreeStoreChange(_ current: [UUID: [Worktree]]) {
        let allWorktrees = current.values.flatMap { $0 }
        let activeIDs = Set(allWorktrees.map(\.id))
        statusStore.reconcile(activeIDs: activeIDs)

        for worktree in allWorktrees {
            statusStore.startWatching(
                worktreeID: worktree.id,
                path: worktree.path,
                kind: worktree.vcsKind
            )
        }
    }

    private func handleShortcutAction(_ action: ShortcutAction) -> Bool {
        shortcutDispatcher.perform(action, activeProject: activeProject) { project in
            openVCS(for: project)
        }
    }

    private func handleCommandShortcut(_ shortcut: CommandShortcut) -> Bool {
        guard let projectID = appState.activeProjectID,
              appState.workspaceRoot(for: projectID) != nil,
              !shortcut.trimmedCommand.isEmpty
        else { return false }
        appState.createCommandTab(projectID: projectID, shortcut: shortcut)
        return true
    }

    private var activeProjectHasSplitWorkspace: Bool {
        guard let project = activeProject,
              let root = appState.workspaceRoot(for: project.id)
        else { return false }
        if case .split = root { return true }
        return false
    }

    private var projectsWithWorkspaces: [Project] {
        var projects = projectStore.projects.filter { appState.workspaceRoot(for: $0.id) != nil }
        if appState.workspaceRoot(for: Project.scratchID) != nil {
            projects.insert(Self.scratchProject, at: 0)
        }
        return projects
    }

    private func sidePanelResizeHandle(onDrag: @escaping (CGFloat) -> Void) -> some View {
        Rectangle().fill(MuxyTheme.border).frame(width: 1)
            .accessibilityHidden(true)
            .overlay {
                Color.clear
                    .frame(width: 5)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in onDrag(v.translation.width) }
                    )
                    .onHover { on in
                        if on { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
            }
    }

    private var activeFileTreeState: FileTreeState? {
        guard let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id)
        else { return nil }
        return fileTreeStates[key]
    }

    private func ensureFileTreeState(for project: Project) {
        guard let key = appState.activeWorktreeKey(for: project.id) else { return }
        let path = activeWorktreePath(for: project)
        if let existing = fileTreeStates[key], existing.rootPath == path { return }
        fileTreeStates[key] = FileTreeState(rootPath: path)
    }

    private var activeEditorState: EditorTabState? {
        guard let project = activeProject else { return nil }
        return appState.activeTab(for: project.id)?.content.editorState
    }

    private var activeEditorFilePath: String? {
        activeEditorState?.filePath
    }

    private func activeEditorCursor() -> (line: Int?, column: Int?) {
        guard let state = activeEditorState else { return (nil, nil) }
        return (state.cursorLine, state.cursorColumn)
    }

    private func syncFileTreeSelection(filePath: String?) {
        guard fileTreePanelVisible,
              let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id),
              let state = fileTreeStates[key]
        else { return }
        if let filePath {
            state.revealFile(at: filePath)
        } else {
            state.clearSelection()
        }
    }

    private func pruneFileTreeStates() {
        let validKeys = validVCSKeys()
        fileTreeStates = fileTreeStates.filter { validKeys.contains($0.key) }
    }

    private func toggleAttachedVCSPanel() {
        guard VCSDisplayMode.current == .attached,
              let project = activeProject
        else {
            vcsPanelVisible = false
            return
        }

        ensureVCSState(for: project)
        let isShowing = !vcsPanelVisible
        vcsPanelVisible = isShowing
        if isShowing {
            fileTreePanelVisible = false
        }
    }

    private func toggleFileTreePanel() {
        guard let project = activeProject else {
            if fileTreePanelVisible {
                fileTreePanelVisible = false
                NotificationCenter.default.post(name: .refocusActiveTerminal, object: nil)
            }
            return
        }

        ensureFileTreeState(for: project)
        let isShowing = !fileTreePanelVisible
        fileTreePanelVisible = isShowing
        if isShowing {
            vcsPanelVisible = false
        } else {
            NotificationCenter.default.post(name: .refocusActiveTerminal, object: nil)
        }
    }

    private var activeVCSState: VCSTabState? {
        guard let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id)
        else { return nil }
        return vcsStates[key]
    }

    private func ensureVCSState(for project: Project) {
        guard let key = appState.activeWorktreeKey(for: project.id) else { return }
        guard vcsStates[key] == nil else { return }
        vcsStates[key] = VCSTabState(projectPath: activeWorktreePath(for: project))
    }

    private func scheduleSidePanelStateSync() {
        sidePanelStateSyncTask?.cancel()
        let signature = vcsEnsureSignature
        sidePanelStateSyncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, signature == vcsEnsureSignature else { return }
            syncVisibleSidePanelStates()
        }
    }

    private func syncVisibleSidePanelStates() {
        guard let project = activeProject else { return }
        if vcsPanelVisible, VCSDisplayMode.current == .attached {
            ensureVCSState(for: project)
        }
        if fileTreePanelVisible {
            ensureFileTreeState(for: project)
        }
    }

    private func activeWorktreePath(for project: Project) -> String {
        guard let key = appState.activeWorktreeKey(for: project.id) else { return project.path }
        return worktreeStore
            .worktree(projectID: project.id, worktreeID: key.worktreeID)?
            .path ?? project.path
    }

    private func openVCS(for project: Project, preferredAreaID: UUID? = nil) {
        VCSDisplayMode.current.route(
            tab: {
                let areaID = preferredAreaID
                    ?? appState.focusedAreaID(for: project.id)
                    ?? appState.workspaceRoot(for: project.id)?.allAreas().first?.id
                guard let areaID else { return }
                appState.dispatch(.createVCSTab(projectID: project.id, areaID: areaID))
            },
            window: { openWindow(id: "vcs") },
            attached: {
                toggleAttachedVCSPanel()
            }
        )
    }

    private func pruneVCSStates() {
        let validKeys = validVCSKeys()
        vcsStates = vcsStates.filter { validKeys.contains($0.key) }
    }

    private func validVCSKeys() -> Set<WorktreeKey> {
        var keys: Set<WorktreeKey> = []
        for project in projectStore.projects {
            for worktree in worktreeStore.list(for: project.id) {
                keys.insert(WorktreeKey(projectID: project.id, worktreeID: worktree.id))
            }
        }
        return keys
    }

    private var vcsPruneSignature: [String] {
        var result: [String] = []
        for project in projectStore.projects {
            result.append(project.id.uuidString)
            for worktree in worktreeStore.list(for: project.id) {
                result.append(worktree.id.uuidString)
            }
        }
        return result
    }

    private var vcsEnsureSignature: String {
        let projectID = appState.activeProjectID?.uuidString ?? ""
        let worktreeID = appState.activeProjectID.flatMap { appState.activeWorktreeID[$0] }?.uuidString ?? ""
        return "\(projectID):\(worktreeID)"
    }

    private var terminalWorkspaceSignature: [String] {
        let projectIDs = Set(projectStore.projects.map(\.id))
        return appState.workspaceRoots.keys
            .filter { projectIDs.contains($0.projectID) }
            .map { "\($0.projectID.uuidString):\($0.worktreeID.uuidString)" }
            .sorted()
    }

    private func presentCloseConfirmation(_ kind: CloseConfirmationKind) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else { return }

        let alert = NSAlert()
        alert.messageText = kind.title
        alert.informativeText = kind.message
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage

        switch kind {
        case .unsavedEditor:
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Don't Save")
            alert.buttons[0].keyEquivalent = "\r"
            alert.buttons[1].keyEquivalent = "\u{1b}"
            alert.buttons[2].keyEquivalent = "d"
            alert.buttons[2].keyEquivalentModifierMask = [.command]
        case .runningProcess:
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            alert.buttons[0].keyEquivalent = "\r"
            alert.buttons[1].keyEquivalent = "\u{1b}"
        }

        if kind == .runningProcess {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don't ask again"
        }

        alert.beginSheetModal(for: window) { response in
            switch kind {
            case .unsavedEditor:
                switch response {
                case .alertFirstButtonReturn:
                    appState.saveAndCloseUnsavedEditorTab()
                case .alertThirdButtonReturn:
                    appState.confirmCloseUnsavedEditorTab()
                default:
                    appState.cancelCloseUnsavedEditorTab()
                }
            case .runningProcess:
                if response == .alertFirstButtonReturn {
                    if alert.suppressionButton?.state == .on {
                        TabCloseConfirmationPreferences.confirmRunningProcess = false
                    }
                    appState.confirmCloseRunningTab()
                } else {
                    appState.cancelCloseRunningTab()
                }
            }
        }
    }

    private func presentSaveErrorAlert(message: String) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else {
            appState.pendingSaveErrorMessage = nil
            return
        }

        let alert = NSAlert()
        alert.messageText = "Could Not Save File"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.buttons[0].keyEquivalent = "\r"

        alert.beginSheetModal(for: window) { _ in
            appState.pendingSaveErrorMessage = nil
        }
    }

    private func presentLayoutApplyBlockedAlert(message: String) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else {
            appState.clearLayoutApplyBlockedMessage()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Cannot Apply Layout"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.buttons[0].keyEquivalent = "\r"

        alert.beginSheetModal(for: window) { _ in
            appState.clearLayoutApplyBlockedMessage()
        }
    }

    private func presentLayoutApplyConfirmation(pending: AppState.PendingLayoutApply) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else {
            appState.cancelApplyLayout()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Apply Layout '\(pending.layoutName)'?"
        alert.informativeText = "All terminals and tabs in this worktree will be closed and replaced with the layout."
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                appState.confirmApplyLayout()
            } else {
                appState.cancelApplyLayout()
            }
        }
    }
}

private struct WindowTitleUpdater: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.title = title
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window, window.title != title else { return }
        window.title = title
    }
}

private struct FileTreeSelectionSync: ViewModifier {
    let filePath: String?
    let panelVisible: Bool
    let sync: (String?) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: filePath) { _, newValue in
                sync(newValue)
            }
            .onChange(of: panelVisible) { _, visible in
                guard visible else { return }
                sync(filePath)
            }
    }
}

private struct NavigationArrowButton: View {
    let symbol: String
    let isEnabled: Bool
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }

    private var foregroundColor: Color {
        guard isEnabled else { return MuxyTheme.fgMuted.opacity(0.35) }
        return hovered ? MuxyTheme.fg : MuxyTheme.fgMuted
    }
}

private struct MainWindowShortcutInterceptor: NSViewRepresentable {
    let onShortcut: (ShortcutAction) -> Bool
    let onCommandShortcut: (CommandShortcut) -> Bool
    let onMouseBack: () -> Void
    let onMouseForward: () -> Void

    func makeNSView(context: Context) -> ShortcutInterceptingView {
        let view = ShortcutInterceptingView()
        view.onShortcut = onShortcut
        view.onCommandShortcut = onCommandShortcut
        view.onMouseBack = onMouseBack
        view.onMouseForward = onMouseForward
        return view
    }

    func updateNSView(_ nsView: ShortcutInterceptingView, context: Context) {
        nsView.onShortcut = onShortcut
        nsView.onCommandShortcut = onCommandShortcut
        nsView.onMouseBack = onMouseBack
        nsView.onMouseForward = onMouseForward
    }
}

private final class ShortcutInterceptingView: NSView {
    var onShortcut: ((ShortcutAction) -> Bool)?
    var onCommandShortcut: ((CommandShortcut) -> Bool)?
    var onMouseBack: (() -> Void)?
    var onMouseForward: (() -> Void)?
    private var mouseMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMouseMonitor()
        } else {
            installMouseMonitorIfNeeded()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              ShortcutContext.isMainWindow(window)
        else { return super.performKeyEquivalent(with: event) }

        let scopes = ShortcutContext.activeScopes(for: window)
        let layerWasActive = CommandShortcutStore.shared.isLayerActive
        if let shortcut = CommandShortcutStore.shared.shortcut(for: event, scopes: scopes) {
            CommandShortcutStore.shared.deactivateLayer()
            _ = onCommandShortcut?(shortcut)
            return true
        }

        if layerWasActive {
            CommandShortcutStore.shared.deactivateLayer()
            return true
        }

        if CommandShortcutStore.shared.matchesPrefix(event: event, scopes: scopes) {
            CommandShortcutStore.shared.activateLayer()
            return true
        }

        if let action = KeyBindingStore.shared.action(for: event, scopes: scopes) {
            if onShortcut?(action) == true {
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    private func installMouseMonitorIfNeeded() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .swipe]) { [weak self] event in
            guard let self,
                  let window = self.window,
                  window.isKeyWindow,
                  ShortcutContext.isMainWindow(window)
            else { return event }
            return self.handleNavigationEvent(event)
        }
    }

    private func handleNavigationEvent(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .otherMouseDown:
            switch event.buttonNumber {
            case 3:
                onMouseBack?()
                return nil
            case 4:
                onMouseForward?()
                return nil
            default:
                return event
            }
        case .swipe:
            if event.deltaX > 0 {
                onMouseBack?()
                return nil
            }
            if event.deltaX < 0 {
                onMouseForward?()
                return nil
            }
            return event
        default:
            return event
        }
    }

    private func removeMouseMonitor() {
        guard let mouseMonitor else { return }
        NSEvent.removeMonitor(mouseMonitor)
        self.mouseMonitor = nil
    }
}

private struct WindowOpenReceiver: View {
    let openWindow: OpenWindowAction

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openVCSWindow)) { _ in
                openWindow(id: "vcs")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openHelpWindow)) { _ in
                openWindow(id: "help")
            }
    }
}
