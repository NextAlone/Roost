import MuxyShared
import SwiftUI

struct TabAreaView: View {
    let area: TabArea
    let isFocused: Bool
    let isActiveProject: Bool
    let showTabStrip: Bool
    let showVCSButton: Bool
    let projectID: UUID
    let onFocus: () -> Void
    let onSelectTab: (UUID) -> Void
    let onCreateTab: () -> Void
    let onCreateVCSTab: () -> Void
    let onCloseTab: (UUID) -> Void
    let onForceCloseTab: (UUID) -> Void
    let onSplit: (SplitDirection) -> Void
    let onDropAction: (TabDragCoordinator.DropResult) -> Void
    @Environment(TabDragCoordinator.self) private var dragCoordinator
    @Environment(AppState.self) private var appState
    @Environment(\.roostHostdClient) private var hostdClient
    @State private var isExternalDragHovering = false
    @State private var externalDragHideTask: Task<Void, any Error>?

    private static let externalDragHideDebounce: Duration = .milliseconds(80)

    private var showsActiveBorder: Bool {
        isFocused && isActiveProject
    }

    private var activeBorderColor: Color {
        MuxyTheme.accent.opacity(0.4)
    }

    private func closeTabs(_ tabIDs: [UUID]) {
        for tabID in tabIDs {
            onCloseTab(tabID)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showTabStrip {
                PaneTabStrip(
                    areaID: area.id,
                    tabs: PaneTabStrip.snapshots(from: area.tabs),
                    activeTabID: area.activeTabID,
                    isFocused: isFocused,
                    showVCSButton: showVCSButton,
                    projectID: projectID,
                    onSelectTab: onSelectTab,
                    onCreateTab: onCreateTab,
                    onCreateAgentTab: { kind in
                        appState.createAgentTab(kind, projectID: projectID, areaID: area.id, hostdClient: hostdClient)
                    },
                    onCreateVCSTab: onCreateVCSTab,
                    onCloseTab: onCloseTab,
                    onCloseOtherTabs: { tabID in
                        closeTabs(area.tabs.filter { $0.id != tabID && !$0.isPinned }.map(\.id))
                    },
                    onCloseTabsToLeft: { tabID in
                        guard let index = area.tabs.firstIndex(where: { $0.id == tabID }) else { return }
                        closeTabs(area.tabs.prefix(index).filter { !$0.isPinned }.map(\.id))
                    },
                    onCloseTabsToRight: { tabID in
                        guard let index = area.tabs.firstIndex(where: { $0.id == tabID }) else { return }
                        closeTabs(area.tabs.suffix(from: index + 1).filter { !$0.isPinned }.map(\.id))
                    },
                    onSplit: onSplit,
                    onDropAction: onDropAction,
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
                Rectangle().fill(MuxyTheme.border).frame(height: 1)
            }
            ZStack {
                ForEach(area.tabs) { tab in
                    let isActive = tab.id == area.activeTabID
                    TabContentView(
                        tab: tab,
                        focused: isActive && isFocused && isActiveProject,
                        visible: isActive,
                        areaID: area.id,
                        onFocus: onFocus,
                        onProcessExit: {
                            if let pane = tab.content.pane {
                                if TabProcessExitPolicy.representsPaneSessionExit(pane) {
                                    let paneID = pane.id
                                    appState.markPaneSessionExited(paneID: paneID)
                                    if let hostdClient {
                                        Task { [hostdClient] in
                                            try? await hostdClient.markExited(sessionID: paneID)
                                        }
                                    }
                                }
                                if TabProcessExitPolicy.shouldForceCloseTabAfterPaneSessionExit(pane) {
                                    onForceCloseTab(tab.id)
                                }
                            } else {
                                onForceCloseTab(tab.id)
                            }
                        },
                        onSplitRequest: { direction, position in
                            appState.dispatch(.splitArea(.init(
                                projectID: projectID,
                                areaID: area.id,
                                direction: direction,
                                position: position
                            )))
                        }
                    )
                    .zIndex(isActive ? 1 : 0)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                }
            }
            .overlay {
                if dragCoordinator.activeDrag != nil, dragCoordinator.hoveredAreaID == area.id,
                   let zone = dragCoordinator.hoveredZone
                {
                    DropZoneHighlight(zone: zone)
                }
            }
        }
        .overlay(alignment: .top) {
            if showsActiveBorder {
                Rectangle()
                    .fill(activeBorderColor)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .leading) {
            if showsActiveBorder {
                Rectangle()
                    .fill(activeBorderColor)
                    .frame(width: 1)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            if showsActiveBorder {
                Rectangle()
                    .fill(activeBorderColor)
                    .frame(width: 1)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if showsActiveBorder {
                Rectangle()
                    .fill(activeBorderColor)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isExternalDragHovering {
                ExternalDragHoverHighlight()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isExternalDragHovering)
        .onReceive(NotificationCenter.default.publisher(for: .externalDragHoverChanged)) { note in
            handleExternalDragHover(note: note)
        }
        .onDisappear {
            externalDragHideTask?.cancel()
        }
        .background {
            if dragCoordinator.activeDrag != nil {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: AreaFramePreferenceKey.self,
                        value: [area.id: geo.frame(in: .named(DragCoordinateSpace.mainWindow))]
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInTerminal)) { _ in
            guard isFocused, isActiveProject else { return }
            guard let tabID = area.activeTabID,
                  let tab = area.tabs.first(where: { $0.id == tabID })
            else { return }
            guard let pane = tab.content.pane else { return }
            TerminalViewRegistry.shared.existingView(for: pane.id)?.startSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveActiveEditor)) { _ in
            guard isFocused, isActiveProject else { return }
            guard let tabID = area.activeTabID,
                  let tab = area.tabs.first(where: { $0.id == tabID })
            else { return }
            guard let editorState = tab.content.editorState else { return }
            Task { @MainActor in
                do {
                    try await editorState.saveFileAsync()
                } catch {
                    appState.pendingSaveErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleExternalDragHover(note: Notification) {
        guard let hovering = note.userInfo?[ExternalDragHoverUserInfoKey.isHovering] as? Bool,
              let notedAreaID = note.userInfo?[ExternalDragHoverUserInfoKey.areaID] as? UUID,
              notedAreaID == area.id
        else { return }
        externalDragHideTask?.cancel()
        if hovering {
            isExternalDragHovering = true
            return
        }
        externalDragHideTask = Task { @MainActor in
            try await Task.sleep(for: Self.externalDragHideDebounce)
            isExternalDragHovering = false
        }
    }
}

private struct ExternalDragHoverHighlight: View {
    var body: some View {
        Rectangle()
            .fill(MuxyTheme.accent.opacity(0.15))
            .overlay(
                Rectangle()
                    .strokeBorder(MuxyTheme.accent.opacity(0.6), lineWidth: 2)
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct TabContentView: View {
    let tab: TerminalTab
    let focused: Bool
    let visible: Bool
    let areaID: UUID
    let onFocus: () -> Void
    let onProcessExit: () -> Void
    let onSplitRequest: (SplitDirection, SplitPosition) -> Void

    var body: some View {
        switch tab.content {
        case let .terminal(pane):
            TerminalPane(
                state: pane,
                focused: focused,
                visible: visible,
                areaID: areaID,
                onFocus: onFocus,
                onProcessExit: onProcessExit,
                onSplitRequest: onSplitRequest
            )
        case let .vcs(vcsState):
            VCSTabView(state: vcsState, focused: focused, onFocus: onFocus)
                .overlay {
                    InactiveWindowClickView(action: onFocus)
                        .accessibilityHidden(true)
                }
        case let .editor(editorState):
            EditorPane(state: editorState, focused: focused, onFocus: onFocus)
                .overlay {
                    InactiveWindowClickView(action: onFocus)
                        .accessibilityHidden(true)
                }
        case let .diffViewer(diffState):
            DiffViewerPane(state: diffState, focused: focused, onFocus: onFocus)
                .overlay {
                    InactiveWindowClickView(action: onFocus)
                        .accessibilityHidden(true)
                }
        }
    }
}
