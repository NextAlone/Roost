import AppKit
import MuxyShared
import SwiftUI

struct ExpandedProjectRow: View {
    let project: Project
    let shortcutIndex: Int?
    let isAnyDragging: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void
    let onRename: (String) -> Void
    let onSetLogo: (String?) -> Void
    let onSetIconColor: (String?) -> Void

    @Environment(AppState.self) private var appState
    @Environment(WorktreeStore.self) private var worktreeStore
    @Environment(\.vcsStatusProbeResolver) private var statusProbeResolver
    @Environment(\.roostHostdClient) private var hostdClient

    @State private var hovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isVcsRepo = false
    @State private var showCreateWorktreeSheet = false
    @State private var logoCropImage: IdentifiableExpandedImage?
    @State private var worktreesExpanded = false
    @State private var isRefreshingWorktrees = false
    @State private var showColorPicker = false
    @State private var expandedWorktreeIDs: Set<UUID> = []
    @State private var pendingAgentKind: AgentKind?

    private var isActive: Bool {
        appState.activeProjectID == project.id
    }

    private var worktrees: [Worktree] {
        worktreeStore.list(for: project.id)
    }

    private var activeWorktreeID: UUID? {
        appState.activeWorktreeID[project.id]
    }

    private var activeWorktree: Worktree? {
        worktrees.first { $0.id == activeWorktreeID }
    }

    private var displayLetter: String {
        String(project.name.prefix(1)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectHeader
            if worktreesExpanded, isVcsRepo {
                worktreeList
            }
        }
        .task(id: project.path) {
            isVcsRepo = VcsKindDetector.isVcsRepository(at: project.path)
            if isActive, isVcsRepo {
                worktreesExpanded = true
            }
        }
        .onChange(of: isActive) { _, active in
            guard active, isVcsRepo else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                worktreesExpanded = true
            }
        }
        .contextMenu {
            Button("Set Logo...") { pickLogoImage() }
            if project.logo != nil {
                Button("Remove Logo") { onSetLogo(nil) }
            }
            Button("Set Icon Color...") { showColorPicker = true }
            if project.iconColor != nil {
                Button("Reset Icon Color") { onSetIconColor(nil) }
            }
            Divider()
            Button("Rename Project") { startRename() }
            if isVcsRepo {
                Divider()
                Button("Refresh Workspaces") { Task { await refreshWorktrees() } }
                Button("New Workspace…") { showCreateWorktreeSheet = true }
            }
            Divider()
            Button("Remove Project", role: .destructive, action: onRemove)
        }
        .sheet(isPresented: $showCreateWorktreeSheet) {
            CreateWorktreeSheet(project: project) { result in
                showCreateWorktreeSheet = false
                handleCreateWorktreeResult(result)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestCreateWorkspaceForAgent)) { note in
            guard appState.activeProjectID == project.id,
                  let raw = note.userInfo?["kind"] as? String,
                  let kind = AgentKind(rawValue: raw)
            else { return }
            pendingAgentKind = kind
            showCreateWorktreeSheet = true
        }
        .sheet(item: $logoCropImage) { item in
            LogoCropperSheet(
                sourceImage: item.image,
                onConfirm: { cropped in
                    logoCropImage = nil
                    let logoPath = ProjectLogoStorage.save(
                        croppedImage: cropped,
                        forProjectID: project.id
                    )
                    onSetLogo(logoPath)
                },
                onCancel: { logoCropImage = nil }
            )
        }
        .popover(isPresented: $isRenaming, arrowEdge: .trailing) {
            ExpandedRenamePopover(
                text: $renameText,
                onCommit: { commitRename() },
                onCancel: { cancelRename() }
            )
        }
        .popover(isPresented: $showColorPicker, arrowEdge: .trailing) {
            ProjectIconColorPicker(selectedID: project.iconColor) { id in
                onSetIconColor(id)
                showColorPicker = false
            }
        }
    }

    private var projectHeader: some View {
        HStack(spacing: ExpandedWorktreeRowLayout.projectColumnSpacing) {
            projectIcon

            Text(project.name)
                .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? MuxyTheme.fg : MuxyTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if isVcsRepo {
                worktreeChevron
            }
        }
        .frame(minHeight: ExpandedWorktreeRowLayout.projectRowMinHeight)
        .padding(.leading, ExpandedWorktreeRowLayout.projectLeadingContentInset)
        .padding(.trailing, ExpandedWorktreeRowLayout.trailingContentInset)
        .background(headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MuxyTheme.border.opacity(0.55))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(projectHeaderAccessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
        .onHover { hovering in
            guard !isAnyDragging else { return }
            hovered = hovering
        }
        .onChange(of: isAnyDragging) { _, dragging in
            if dragging { hovered = false }
        }
        .onTapGesture {
            guard !isAnyDragging else { return }
            onSelect()
        }
        .overlay {
            if showShortcutBadge, let shortcutIndex,
               let action = ShortcutAction.projectAction(for: shortcutIndex)
            {
                ShortcutBadge(label: KeyBindingStore.shared.displayString(for: action))
            }
        }
    }

    private var worktreeChevron: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                worktreesExpanded.toggle()
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(MuxyTheme.fgDim)
                .rotationEffect(.degrees(worktreesExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.15), value: worktreesExpanded)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(worktreesExpanded ? "Collapse Workspaces" : "Expand Workspaces")
    }

    private var projectIcon: some View {
        let logo = resolvedLogo
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(iconBackground(hasLogo: logo != nil))

            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: ExpandedWorktreeRowLayout.projectIconSize,
                        height: ExpandedWorktreeRowLayout.projectIconSize
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Text(displayLetter)
                    .font(.system(size: ExpandedWorktreeRowLayout.projectLetterFontSize, weight: .bold))
                    .foregroundStyle(letterForeground)
            }
        }
        .frame(
            width: ExpandedWorktreeRowLayout.projectIconSize,
            height: ExpandedWorktreeRowLayout.projectIconSize
        )
    }

    private var worktreeList: some View {
        VStack(spacing: 0) {
            ForEach(worktrees) { worktree in
                VStack(alignment: .leading, spacing: 0) {
                    let selected = Self.isWorktreeSelected(
                        projectID: project.id,
                        worktreeID: worktree.id,
                        activeProjectID: appState.activeProjectID,
                        activeWorktreeID: activeWorktreeID
                    )
                    let key = WorktreeKey(projectID: project.id, worktreeID: worktree.id)
                    let agentActivitySummary = agentActivitySummary(for: worktree, selected: selected)
                    ExpandedWorktreeRow(
                        projectID: project.id,
                        worktree: worktree,
                        selected: selected,
                        agentActivitySummary: agentActivitySummary,
                        onSelect: {
                            appState.selectWorktree(projectID: project.id, worktree: worktree)

                            if agentActivitySummary?.dominantState == .completed {
                                appState.clearCompletedAgentActivity(for: key)
                            }
                        },
                        onRename: { newName in
                            worktreeStore.rename(
                                worktreeID: worktree.id,
                                in: project.id,
                                to: newName
                            )
                        },
                        onDoubleClick: {
                            toggleWorktreeExpansion(worktree.id)
                        },
                        onRemove: worktree.canBeRemoved ? {
                            Task { await requestRemove(worktree: worktree) }
                        } : nil
                    )

                    if expandedWorktreeIDs.contains(worktree.id) {
                        sessionList(for: worktree)
                    }
                }
            }

            ExpandedNewWorktreeButton {
                showCreateWorktreeSheet = true
            }

            if !untrackedJjWorkspaceNames.isEmpty {
                UntrackedJjWorkspacesHint(names: untrackedJjWorkspaceNames) { name in
                    importUntrackedJjWorkspace(name: name)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private func agentActivitySummary(for worktree: Worktree, selected: Bool) -> SidebarAgentActivitySummary? {
        let key = WorktreeKey(projectID: project.id, worktreeID: worktree.id)
        return SidebarAgentActivityResolver.summary(
            tabs: appState.allTabs(forKey: key),
            activeTabID: selected ? appState.focusedArea(for: project.id)?.activeTabID : nil
        )
    }

    private var untrackedJjWorkspaceNames: [String] {
        worktreeStore.untrackedJjWorkspaces(for: project.id)
    }

    private func importUntrackedJjWorkspace(name: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the on-disk path for jj workspace '\(name)'"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try worktreeStore.importExternalJjWorkspace(
                name: name,
                path: url.path(percentEncoded: false),
                into: project.id
            )
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not import jj workspace '\(name)'"
            alert.informativeText = importErrorMessage(error)
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func importErrorMessage(_ error: Error) -> String {
        guard let typed = error as? WorktreeStore.ImportExternalJjWorkspaceError else {
            return error.localizedDescription
        }
        switch typed {
        case let .pathDoesNotExist(path):
            return "Path does not exist: \(path)"
        case let .pathNotJjWorkspace(path):
            return "Selected directory has no .jj/ inside, so it is not a jj workspace: \(path)"
        case let .duplicateName(name):
            return "A workspace named '\(name)' is already tracked for this project."
        case let .duplicatePath(path):
            return "A workspace at this path is already tracked: \(path)"
        }
    }

    private var projectHeaderAccessibilityLabel: String {
        var label = project.name
        if isVcsRepo, let worktree = activeWorktree {
            label += ", workspace: \(worktree.displayWorkspaceName)"
        }
        return label
    }

    private var resolvedLogo: NSImage? {
        guard let filename = project.logo else { return nil }
        return NSImage(contentsOfFile: ProjectLogoStorage.logoPath(for: filename))
    }

    private func iconBackground(hasLogo: Bool) -> AnyShapeStyle {
        if hasLogo { return AnyShapeStyle(Color.clear) }
        if let tint = ProjectIconColor.color(for: project.iconColor) {
            return AnyShapeStyle(hovered ? tint.opacity(0.85) : tint)
        }
        if hovered { return AnyShapeStyle(MuxyTheme.hover) }
        return AnyShapeStyle(MuxyTheme.surface)
    }

    private var letterForeground: Color {
        if let foreground = ProjectIconColor.foreground(for: project.iconColor) {
            return foreground
        }
        return isActive ? MuxyTheme.fg : MuxyTheme.fgMuted
    }

    private var headerBackground: AnyShapeStyle {
        if isActive { return AnyShapeStyle(MuxyTheme.accentSoft) }
        if hovered { return AnyShapeStyle(MuxyTheme.hover) }
        return AnyShapeStyle(Color.clear)
    }

    private var showShortcutBadge: Bool {
        guard let shortcutIndex,
              let action = ShortcutAction.projectAction(for: shortcutIndex),
              let combo = KeyBindingStore.shared.combo(for: action)
        else { return false }
        return ModifierKeyMonitor.shared.isHolding(
            modifiers: combo.modifiers
        )
    }

    private func pickLogoImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Logo Image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url)
        else { return }

        logoCropImage = IdentifiableExpandedImage(image: image)
    }

    private func handleCreateWorktreeResult(_ result: CreateWorktreeResult) {
        let pending = pendingAgentKind
        pendingAgentKind = nil
        switch result {
        case let .created(worktree, runSetup):
            appState.selectWorktree(projectID: project.id, worktree: worktree)
            worktreesExpanded = true
            if let pending {
                appState.createAgentTab(pending, projectID: project.id, hostdClient: hostdClient)
            }
            if runSetup,
               let paneID = appState.focusedArea(for: project.id)?.activeTab?.content.pane?.id
            {
                Task {
                    await WorktreeSetupRunner.run(
                        sourceProjectPath: project.path,
                        paneID: paneID
                    )
                }
            }
        case .cancelled:
            break
        }
    }

    private func requestRemove(worktree: Worktree) async {
        let probe = statusProbeResolver.probe(worktree.vcsKind)
        let hasChanges = await probe.hasUncommittedChanges(at: worktree.path)
        WorkspaceRemovalConfirmation.present(
            worktree: worktree,
            hasUncommittedChanges: hasChanges
        ) { deleteWorkspaceDirectory in
            performRemove(worktree: worktree, deleteWorkspaceDirectory: deleteWorkspaceDirectory)
        }
    }

    private func performRemove(worktree: Worktree, deleteWorkspaceDirectory: Bool) {
        let repoPath = project.path
        let remaining = worktrees.filter { $0.id != worktree.id }
        let replacement = remaining.first(where: { $0.id == activeWorktreeID })
            ?? remaining.first(where: { $0.isPrimary })
            ?? remaining.first
        appState.removeWorktree(
            projectID: project.id,
            worktree: worktree,
            replacement: replacement
        )
        worktreeStore.remove(worktreeID: worktree.id, from: project.id)
        guard deleteWorkspaceDirectory else { return }
        Task.detached {
            await WorktreeStore.cleanupOnDisk(
                worktree: worktree,
                repoPath: repoPath
            )
        }
    }

    private func startRename() {
        renameText = project.name
        isRenaming = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }

    private func refreshWorktrees() async {
        await WorktreeRefreshHelper.refresh(
            project: project,
            appState: appState,
            worktreeStore: worktreeStore,
            isRefreshing: $isRefreshingWorktrees
        )
    }

    private func toggleWorktreeExpansion(_ id: UUID) {
        if expandedWorktreeIDs.contains(id) {
            expandedWorktreeIDs.remove(id)
        } else {
            expandedWorktreeIDs.insert(id)
        }
    }

    @ViewBuilder
    private func sessionList(for worktree: Worktree) -> some View {
        let key = WorktreeKey(projectID: project.id, worktreeID: worktree.id)
        let tabs = appState.allTabs(forKey: key)
        if tabs.isEmpty {
            Text("No sessions")
                .font(.system(size: 10))
                .foregroundStyle(MuxyTheme.fgDim)
                .padding(.leading, ExpandedWorktreeRowLayout.worktreeTitleLeadingEdge)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(tabs) { tab in
                    SessionRow(
                        tab: tab,
                        isActive: isSessionActive(tab: tab, key: key),
                        onSelect: { selectSession(tab: tab, worktree: worktree, key: key) }
                    )
                    .padding(.leading, ExpandedWorktreeRowLayout.worktreeTitleLeadingEdge)
                }
            }
        }
    }

    private func isSessionActive(tab: TerminalTab, key: WorktreeKey) -> Bool {
        guard isActive else { return false }
        guard let activeWorktreeID = appState.activeWorktreeID[project.id] else { return false }
        let activeKey = WorktreeKey(projectID: project.id, worktreeID: activeWorktreeID)
        guard activeKey == key else { return false }
        return appState.focusedArea(for: project.id)?.activeTabID == tab.id
    }

    nonisolated static func isWorktreeSelected(
        projectID: UUID,
        worktreeID: UUID,
        activeProjectID: UUID?,
        activeWorktreeID: UUID?
    ) -> Bool {
        activeProjectID == projectID && activeWorktreeID == worktreeID
    }

    private func selectSession(tab: TerminalTab, worktree: Worktree, key: WorktreeKey) {
        if appState.activeWorktreeID[project.id] != worktree.id {
            appState.selectWorktree(projectID: project.id, worktree: worktree)
        }
        guard let area = appState.workspaceRoots[key]?.allAreas().first(where: {
            $0.tabs.contains(where: { $0.id == tab.id })
        })
        else { return }
        appState.dispatch(.selectTab(projectID: project.id, areaID: area.id, tabID: tab.id))
    }
}

enum ExpandedWorktreeRowLayout {
    static let selectedStripeWidth: CGFloat = 3
    static let projectLeadingContentInset: CGFloat = AddProjectButtonLayout.expandedLeadingContentInset
    static let projectIconSize: CGFloat = AddProjectButtonLayout.expandedIconSize
    static let projectLetterFontSize: CGFloat = 13
    static let projectColumnSpacing: CGFloat = AddProjectButtonLayout.expandedColumnSpacing
    static let projectTitleLeadingEdge: CGFloat = projectLeadingContentInset + projectIconSize + projectColumnSpacing
    static let worktreeLeadingContentInset: CGFloat = 24
    static let newWorktreeLeadingContentInset: CGFloat = worktreeLeadingContentInset
    static let worktreeMarkerWidth: CGFloat = 18
    static let newWorktreeMarkerWidth: CGFloat = worktreeMarkerWidth
    static let treeColumnSpacing: CGFloat = 6
    static let worktreeTitleLeadingEdge: CGFloat = worktreeLeadingContentInset + worktreeMarkerWidth + treeColumnSpacing
    static let newWorktreeTitleLeadingEdge: CGFloat = newWorktreeLeadingContentInset + newWorktreeMarkerWidth + treeColumnSpacing
    static let leadingContentInset: CGFloat = worktreeLeadingContentInset
    static let trailingContentInset: CGFloat = AddProjectButtonLayout.expandedTrailingContentInset
    static let statusDotHeight: CGFloat = AgentActivityStatusBadgeLayout.height
    static let projectRowMinHeight: CGFloat = AddProjectButtonLayout.expandedRowHeight
    static let worktreeRowMinHeight: CGFloat = 30
    static let newWorktreeRowMinHeight: CGFloat = worktreeRowMinHeight
    static let minContentHeight: CGFloat = worktreeRowMinHeight
}

enum ExpandedWorktreeRowClickAction {
    case select
    case doubleClick
}

enum ExpandedWorktreeRowClickPolicy {
    static func action(forClickCount clickCount: Int) -> ExpandedWorktreeRowClickAction {
        clickCount >= 2 ? .doubleClick : .select
    }
}

private struct ExpandedWorktreeRow: View {
    let projectID: UUID
    let worktree: Worktree
    let selected: Bool
    let agentActivitySummary: SidebarAgentActivitySummary?
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onDoubleClick: () -> Void
    let onRemove: (() -> Void)?

    @Environment(WorkspaceStatusStore.self) private var statusStore
    @State private var hovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    private var displayName: String {
        worktree.displayWorkspaceName
    }

    private var branchLabel: String? {
        guard let branch = worktree.branch, !branch.isEmpty else { return nil }
        guard branch.caseInsensitiveCompare(displayName) != .orderedSame else { return nil }
        return branch
    }

    var body: some View {
        HStack(spacing: ExpandedWorktreeRowLayout.treeColumnSpacing) {
            WorktreeTreeMarker()
                .frame(width: ExpandedWorktreeRowLayout.worktreeMarkerWidth)

            if isRenaming {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
            } else {
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? MuxyTheme.fg : MuxyTheme.fgMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let branch = branchLabel {
                        Text(branch)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MuxyTheme.fgDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let label = worktree.vcsKind.sidebarWarningBadgeLabel {
                        VcsWarningBadge(label: label)
                    }
                    if let sidebarStatus {
                        WorkspaceStatusBadge(status: sidebarStatus)
                    }
                }
            }

            Spacer(minLength: 2)

            if let agentActivitySummary, agentActivitySummary.showsSidebarStatusDots {
                AgentActivityDotStack(dots: agentActivitySummary.dots)
            }
        }
        .frame(height: ExpandedWorktreeRowLayout.worktreeRowMinHeight)
        .padding(.leading, ExpandedWorktreeRowLayout.worktreeLeadingContentInset)
        .padding(.trailing, ExpandedWorktreeRowLayout.trailingContentInset)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if selected {
                Capsule()
                    .fill(MuxyTheme.accent)
                    .frame(width: ExpandedWorktreeRowLayout.selectedStripeWidth)
                    .padding(.vertical, 4)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .background {
            SidebarMouseDownActionView { clickCount in
                handleMouseDown(clickCount: clickCount)
            }
        }
        .accessibilityAction {
            guard !isRenaming else { return }
            onSelect()
        }
        .contextMenu {
            if worktree.isPrimary {
                Text("Default workspace").font(.system(size: 11))
            } else if let onRemove {
                Button("Rename") { startRename() }
                Divider()
                Button("Remove", role: .destructive, action: onRemove)
            } else {
                Button("Rename") { startRename() }
                Divider()
                Text("External workspace").font(.system(size: 11))
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MuxyTheme.border.opacity(0.45))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(worktreeAccessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
    }

    private func handleMouseDown(clickCount: Int) {
        guard !isRenaming else { return }
        switch ExpandedWorktreeRowClickPolicy.action(forClickCount: clickCount) {
        case .select:
            onSelect()
        case .doubleClick:
            onDoubleClick()
        }
    }

    private var worktreeAccessibilityLabel: String {
        var label = displayName
        if let branch = branchLabel { label += ", branch: \(branch)" }
        if sidebarStatus == .conflicted { label += ", conflicted" }
        if let agentActivitySummary {
            label += ", \(agentActivitySummary.accessibilityLabel)"
        }
        return label
    }

    private var sidebarStatus: WorkspaceStatus? {
        statusStore.status(forWorktreeID: worktree.id).sidebarRowBadgeStatus
    }

    private var rowBackground: AnyShapeStyle {
        if agentActivitySummary?.dominantState == .needsInput {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    MuxyTheme.diffRemoveFg.opacity(0.16),
                    MuxyTheme.diffRemoveFg.opacity(0.06),
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
        }
        if agentActivitySummary?.dominantState == .completed {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    MuxyTheme.diffAddFg.opacity(0.13),
                    MuxyTheme.diffAddFg.opacity(0.04),
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
        }
        if agentActivitySummary?.dominantState == .running {
            return AnyShapeStyle(LinearGradient(
                colors: [
                    MuxyTheme.accent.opacity(0.12),
                    MuxyTheme.accent.opacity(0.04),
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
        }
        if hovered { return AnyShapeStyle(MuxyTheme.hover) }
        return AnyShapeStyle(Color.clear)
    }

    private func startRename() {
        renameText = worktree.name
        isRenaming = true
        renameFieldFocused = true
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { onRename(trimmed) }
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }
}

private struct WorktreeTreeMarker: View {
    var body: some View {
        Text("·")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(MuxyTheme.fgDim.opacity(0.72))
            .frame(maxWidth: .infinity)
    }
}

private struct ExpandedNewWorktreeButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: ExpandedWorktreeRowLayout.treeColumnSpacing) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(hovered ? MuxyTheme.accent : MuxyTheme.fgDim)
                    .frame(width: ExpandedWorktreeRowLayout.newWorktreeMarkerWidth)
                Text("New Workspace")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(hovered ? MuxyTheme.accent : MuxyTheme.fgDim)
                Spacer()
            }
            .frame(height: ExpandedWorktreeRowLayout.newWorktreeRowMinHeight)
            .padding(.leading, ExpandedWorktreeRowLayout.newWorktreeLeadingContentInset)
            .padding(.trailing, ExpandedWorktreeRowLayout.trailingContentInset)
            .background(hovered ? MuxyTheme.hover : Color.clear)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(MuxyTheme.border.opacity(0.45))
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("New Workspace")
    }
}

private struct AgentActivityDotStack: View {
    let dots: [SidebarAgentActivityDot]

    var body: some View {
        HStack(spacing: -4) {
            ForEach(dots) { dot in
                AgentActivityStackDot(state: dot.state)
            }
        }
        .frame(height: ExpandedWorktreeRowLayout.statusDotHeight)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var helpText: String {
        let parts: [String] = AgentActivityState.allCases.compactMap { state in
            let count = dots.count { $0.state == state }
            guard count > 0 else { return nil }
            return "\(count) \(state.accessibilityLabel.lowercased())"
        }
        return parts.joined(separator: ", ")
    }
}

private struct AgentActivityStackDot: View {
    let state: AgentActivityState

    var body: some View {
        AgentActivityStatusBadge(state: state)
    }
}

private struct VcsWarningBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(MuxyTheme.diffRemoveFg)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(MuxyTheme.diffRemoveFg.opacity(0.14), in: Capsule())
    }
}

extension VcsKind {
    var sidebarWarningBadgeLabel: String? {
        self == .jj ? nil : rawValue.uppercased()
    }
}

private struct ExpandedRenamePopover: View {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text("Rename Project")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            TextField("Project name", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit { onCommit() }
                .onExitCommand { onCancel() }
        }
        .padding(12)
        .frame(width: 200)
        .onAppear { isFocused = true }
    }
}

private struct IdentifiableExpandedImage: Identifiable {
    let id = UUID()
    let image: NSImage
}

private struct UntrackedJjWorkspacesHint: View {
    let names: [String]
    let onImport: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(MuxyTheme.fgDim)
                Text("\(names.count) external jj workspace\(names.count == 1 ? "" : "s") detected")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MuxyTheme.fgMuted)
            }
            ForEach(names, id: \.self) { name in
                Button(
                    action: { onImport(name) },
                    label: {
                        HStack(spacing: 4) {
                            Text(name)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(MuxyTheme.fgDim)
                            Spacer(minLength: 6)
                            Text("Bind…")
                                .font(.system(size: 9))
                                .foregroundStyle(MuxyTheme.accent)
                        }
                        .contentShape(Rectangle())
                    }
                )
                .buttonStyle(.plain)
                .padding(.leading, 14)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
