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

    @AppStorage(GeneralSettingsKeys.autoExpandWorktreesOnProjectSwitch)
    private var autoExpandWorktrees = false

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
            if autoExpandWorktrees, isActive, isVcsRepo {
                worktreesExpanded = true
            }
        }
        .onChange(of: isActive) { _, active in
            guard autoExpandWorktrees, active, isVcsRepo else { return }
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
        HStack(spacing: 8) {
            projectIcon

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? MuxyTheme.fg : MuxyTheme.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isVcsRepo, let worktree = activeWorktree {
                    Text(worktree.isPrimary ? "primary" : worktree.name)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MuxyTheme.fgDim)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            if isVcsRepo {
                worktreeChevron
            }
        }
        .padding(4)
        .background(headerBackground, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
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
            if isActive, isVcsRepo {
                withAnimation(.easeInOut(duration: 0.15)) {
                    worktreesExpanded.toggle()
                }
            } else {
                onSelect()
            }
        }
        .overlay {
            if showShortcutBadge, let shortcutIndex,
               let action = ShortcutAction.projectAction(for: shortcutIndex)
            {
                ShortcutBadge(label: KeyBindingStore.shared.combo(for: action).displayString)
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
        let unread = NotificationStore.shared.unreadCount(for: project.id)
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(iconBackground(hasLogo: logo != nil))

            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(displayLetter)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(letterForeground)
            }
        }
        .frame(width: 28, height: 28)
        .overlay(alignment: .topTrailing) {
            if unread > 0 {
                NotificationBadge(count: unread)
                    .offset(x: 4, y: -4)
            }
        }
    }

    private var worktreeList: some View {
        VStack(spacing: 1) {
            ForEach(worktrees) { worktree in
                VStack(alignment: .leading, spacing: 0) {
                    ExpandedWorktreeRow(
                        projectID: project.id,
                        worktree: worktree,
                        selected: worktree.id == activeWorktreeID,
                        onSelect: {
                            appState.selectWorktree(projectID: project.id, worktree: worktree)
                        },
                        onRename: { newName in
                            worktreeStore.rename(
                                worktreeID: worktree.id,
                                in: project.id,
                                to: newName
                            )
                        },
                        onRemove: worktree.canBeRemoved ? {
                            Task { await requestRemove(worktree: worktree) }
                        } : nil
                    )
                    .onTapGesture(count: 2) {
                        toggleWorktreeExpansion(worktree.id)
                    }

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
        .padding(.top, 2)
        .padding(.bottom, 4)
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
            label += ", workspace: \(worktree.isPrimary ? "primary" : worktree.name)"
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
              let action = ShortcutAction.projectAction(for: shortcutIndex)
        else { return false }
        return ModifierKeyMonitor.shared.isHolding(
            modifiers: KeyBindingStore.shared.combo(for: action).modifiers
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
                appState.createAgentTab(pending, projectID: project.id)
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
        if !hasChanges {
            performRemove(worktree: worktree)
            return
        }
        presentRemoveConfirmation(worktree: worktree)
    }

    private func presentRemoveConfirmation(worktree: Worktree) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              window.attachedSheet == nil
        else { return }

        let alert = NSAlert()
        alert.messageText = "Remove workspace \"\(worktree.name)\"?"
        alert.informativeText = "This workspace has uncommitted changes. Removing it will permanently discard them."
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            performRemove(worktree: worktree)
        }
    }

    private func performRemove(worktree: Worktree) {
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
                .padding(.leading, 24)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(tabs) { tab in
                    SessionRow(
                        tab: tab,
                        isActive: isSessionActive(tab: tab, key: key),
                        onSelect: { selectSession(tab: tab, worktree: worktree, key: key) }
                    )
                    .padding(.leading, 16)
                }
            }
        }
    }

    private func isSessionActive(tab: TerminalTab, key: WorktreeKey) -> Bool {
        guard let activeWorktreeID = appState.activeWorktreeID[project.id] else { return false }
        let activeKey = WorktreeKey(projectID: project.id, worktreeID: activeWorktreeID)
        guard activeKey == key else { return false }
        return appState.focusedArea(for: project.id)?.activeTabID == tab.id
    }

    private func selectSession(tab: TerminalTab, worktree: Worktree, key: WorktreeKey) {
        if appState.activeWorktreeID[project.id] != worktree.id {
            appState.selectWorktree(projectID: project.id, worktree: worktree)
        }
        guard let area = appState.workspaceRoots[key]?.allAreas().first(where: {
            $0.tabs.contains(where: { $0.id == tab.id })
        }) else { return }
        appState.dispatch(.selectTab(projectID: project.id, areaID: area.id, tabID: tab.id))
    }
}

private struct ExpandedWorktreeRow: View {
    let projectID: UUID
    let worktree: Worktree
    let selected: Bool
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onRemove: (() -> Void)?

    @Environment(WorkspaceStatusStore.self) private var statusStore
    @State private var hovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    private var displayName: String {
        if worktree.isPrimary, worktree.name.isEmpty { return "main" }
        return worktree.name
    }

    private var branchLabel: String? {
        guard let branch = worktree.branch, !branch.isEmpty else { return nil }
        guard branch.caseInsensitiveCompare(displayName) != .orderedSame else { return nil }
        return branch
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(selected ? MuxyTheme.accent : MuxyTheme.fgDim.opacity(0.35))
                .frame(width: 5, height: 5)

            if isRenaming {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                    .focused($renameFieldFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? MuxyTheme.fg : MuxyTheme.fgMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if worktree.isPrimary {
                            PrimaryBadge()
                        }
                        if worktree.vcsKind == .jj {
                            JjBadge()
                        }
                        WorkspaceStatusBadge(status: statusStore.status(forWorktreeID: worktree.id))
                    }

                    if let branch = branchLabel {
                        Text(branch)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MuxyTheme.fgDim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer(minLength: 2)

            worktreeUnreadBadge

            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(MuxyTheme.accent)
                .frame(width: 18, height: 18)
                .opacity(selected ? 1 : 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovered = $0 }
        .onTapGesture {
            guard !isRenaming else { return }
            onSelect()
        }
        .contextMenu {
            if worktree.isPrimary {
                Text("Primary workspace").font(.system(size: 11))
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(worktreeAccessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
    }

    private var worktreeAccessibilityLabel: String {
        var label = displayName
        if worktree.isPrimary { label += ", primary" }
        if let branch = branchLabel { label += ", branch: \(branch)" }
        return label
    }

    @ViewBuilder
    private var worktreeUnreadBadge: some View {
        let unread = NotificationStore.shared.unreadCount(for: projectID, worktreeID: worktree.id)
        if unread > 0 {
            NotificationBadge(count: unread)
        }
    }

    private var rowBackground: AnyShapeStyle {
        if selected { return AnyShapeStyle(MuxyTheme.accentSoft) }
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

private struct ExpandedNewWorktreeButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(hovered ? MuxyTheme.accent : MuxyTheme.fgDim)
                Text("New Workspace")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(hovered ? MuxyTheme.accent : MuxyTheme.fgDim)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("New Workspace")
    }
}

private struct PrimaryBadge: View {
    var body: some View {
        Text("PRIMARY")
            .font(.system(size: 8, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(MuxyTheme.fgDim)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(MuxyTheme.surface, in: Capsule())
    }
}

private struct JjBadge: View {
    var body: some View {
        Text("JJ")
            .font(.system(size: 8, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(MuxyTheme.accent)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(MuxyTheme.accent.opacity(0.15), in: Capsule())
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
                Button(action: { onImport(name) }) {
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
                .buttonStyle(.plain)
                .padding(.leading, 14)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
