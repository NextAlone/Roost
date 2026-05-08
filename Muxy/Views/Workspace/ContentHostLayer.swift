import SwiftUI

struct ContentHostLayer: View {
    let root: SplitNode
    let focusedAreaID: UUID?
    let isActiveProject: Bool
    let projectID: UUID
    @Environment(AppState.self) private var appState
    @Environment(\.activeWorktreeKey) private var worktreeKey
    @Environment(\.roostHostdClient) private var hostdClient
    @Environment(GhosttyService.self) private var ghostty
    @State private var editorSettings = EditorSettings.shared

    var body: some View {
        GeometryReader { geo in
            let frames = root.pixelFrames(in: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(entries(frames: frames), id: \.id) { entry in
                    paneView(for: entry)
                }
            }
        }
    }

    @ViewBuilder
    private func paneView(for entry: Entry) -> some View {
        switch entry {
        case let .terminal(t):
            if t.shouldMountBridge {
                TerminalBridge(
                    state: t.pane,
                    focused: t.isFocused,
                    areaID: t.areaID,
                    onFocus: { dispatchFocus(areaID: t.areaID) },
                    onProcessExit: { handleProcessExit(tabID: t.tabID, areaID: t.areaID) },
                    onSplitRequest: { direction, position in
                        dispatchSplit(areaID: t.areaID, direction: direction, position: position)
                    }
                )
                .frame(width: t.contentRect.width, height: t.contentRect.height)
                .offset(x: t.contentRect.minX, y: t.contentRect.minY)
                .opacity(t.isVisible ? 1 : 0)
                .allowsHitTesting(t.isVisible)
                .zIndex(t.isVisible ? 1 : 0)
                .id(t.tabID)
            }
        case let .editor(e):
            editorView(for: e)
                .frame(width: e.contentRect.width, height: e.contentRect.height)
                .offset(x: e.contentRect.minX, y: e.contentRect.minY)
                .opacity(e.isVisible && e.isEditorVisuallyShown ? 1 : 0)
                .allowsHitTesting(e.isVisible && e.isEditorVisuallyShown)
                .zIndex(e.isVisible ? 1 : 0)
                .id(e.tabID)
        case let .diff(d):
            DiffViewerPane(
                state: d.state,
                focused: d.isFocused,
                onFocus: { dispatchFocus(areaID: d.areaID) }
            )
            .overlay {
                InactiveWindowClickView(action: { dispatchFocus(areaID: d.areaID) })
                    .accessibilityHidden(true)
            }
            .frame(width: d.contentRect.width, height: d.contentRect.height)
            .offset(x: d.contentRect.minX, y: d.contentRect.minY)
            .opacity(d.isVisible ? 1 : 0)
            .allowsHitTesting(d.isVisible)
            .zIndex(d.isVisible ? 1 : 0)
            .id(d.tabID)
        case let .jjDiff(d):
            JjDiffViewerPane(
                state: d.state,
                focused: d.isFocused,
                onFocus: { dispatchFocus(areaID: d.areaID) }
            )
            .overlay {
                InactiveWindowClickView(action: { dispatchFocus(areaID: d.areaID) })
                    .accessibilityHidden(true)
            }
            .frame(width: d.contentRect.width, height: d.contentRect.height)
            .offset(x: d.contentRect.minX, y: d.contentRect.minY)
            .opacity(d.isVisible ? 1 : 0)
            .allowsHitTesting(d.isVisible)
            .zIndex(d.isVisible ? 1 : 0)
            .id(d.tabID)
        }
    }

    private enum Entry: Identifiable {
        case terminal(TerminalEntry)
        case editor(EditorEntry)
        case diff(DiffEntry)
        case jjDiff(JjDiffEntry)

        var id: UUID {
            switch self {
            case let .terminal(t): t.tabID
            case let .editor(e): e.tabID
            case let .diff(d): d.tabID
            case let .jjDiff(d): d.tabID
            }
        }
    }

    private struct TerminalEntry {
        let tabID: UUID
        let areaID: UUID
        let pane: TerminalPaneState
        let contentRect: CGRect
        let isVisible: Bool
        let isFocused: Bool
        let shouldMountBridge: Bool
    }

    private struct EditorEntry {
        let tabID: UUID
        let areaID: UUID
        let state: EditorTabState
        let contentRect: CGRect
        let isVisible: Bool
        let isFocused: Bool
        let isEditorVisuallyShown: Bool
    }

    private struct DiffEntry {
        let tabID: UUID
        let areaID: UUID
        let state: DiffViewerTabState
        let contentRect: CGRect
        let isVisible: Bool
        let isFocused: Bool
    }

    private struct JjDiffEntry {
        let tabID: UUID
        let areaID: UUID
        let state: JjDiffViewerTabState
        let contentRect: CGRect
        let isVisible: Bool
        let isFocused: Bool
    }

    private func entries(frames: [UUID: CGRect]) -> [Entry] {
        let stripsShown = !rootIsTabArea
        return root.allAreas().flatMap { area -> [Entry] in
            guard let areaFrame = frames[area.id] else { return [] }
            let tabContentRect = Self.tabContentRect(in: areaFrame, hasStrip: stripsShown)
            return area.tabs.flatMap { tab -> [Entry] in
                let isActiveTab = tab.id == area.activeTabID
                let isFocused = isActiveProject && isActiveTab && focusedAreaID == area.id
                switch tab.content {
                case let .terminal(pane):
                    let shouldMount = pane.hostdRuntimeOwnership != .hostdOwnedProcess
                        || pane.hostdAttachState == .ready
                    return [.terminal(TerminalEntry(
                        tabID: tab.id,
                        areaID: area.id,
                        pane: pane,
                        contentRect: tabContentRect,
                        isVisible: isActiveTab,
                        isFocused: isFocused,
                        shouldMountBridge: shouldMount
                    ))]
                case let .editor(state):
                    let editorRect = Self.editorContentRect(in: tabContentRect)
                    let shows = !state.awaitingLargeFileConfirmation
                        && !state.isLoading
                        && state.errorMessage == nil
                    return [.editor(EditorEntry(
                        tabID: tab.id,
                        areaID: area.id,
                        state: state,
                        contentRect: editorRect,
                        isVisible: isActiveTab,
                        isFocused: isFocused,
                        isEditorVisuallyShown: shows
                    ))]
                case let .diffViewer(state):
                    return [.diff(DiffEntry(
                        tabID: tab.id,
                        areaID: area.id,
                        state: state,
                        contentRect: tabContentRect,
                        isVisible: isActiveTab,
                        isFocused: isFocused
                    ))]
                case let .jjDiffViewer(state):
                    return [.jjDiff(JjDiffEntry(
                        tabID: tab.id,
                        areaID: area.id,
                        state: state,
                        contentRect: tabContentRect,
                        isVisible: isActiveTab,
                        isFocused: isFocused
                    ))]
                case .vcs:
                    return []
                }
            }
        }
    }

    private var rootIsTabArea: Bool {
        if case .tabArea = root { return true }
        return false
    }

    static let stripHeight: CGFloat = 33
    static let editorBreadcrumbHeight: CGFloat = 33

    private static func tabContentRect(in areaFrame: CGRect, hasStrip: Bool) -> CGRect {
        let inset: CGFloat = hasStrip ? stripHeight : 0
        return CGRect(
            x: areaFrame.minX,
            y: areaFrame.minY + inset,
            width: areaFrame.width,
            height: max(0, areaFrame.height - inset)
        )
    }

    private static func editorContentRect(in tabContentRect: CGRect) -> CGRect {
        CGRect(
            x: tabContentRect.minX,
            y: tabContentRect.minY + editorBreadcrumbHeight,
            width: tabContentRect.width,
            height: max(0, tabContentRect.height - editorBreadcrumbHeight)
        )
    }

    @ViewBuilder
    private func editorView(for e: EditorEntry) -> some View {
        if e.state.isMarkdownFile {
            MarkdownPaneContent(
                state: e.state,
                focused: e.isFocused,
                onFocus: { dispatchFocus(areaID: e.areaID) }
            )
        } else {
            CodeEditorView(
                state: e.state,
                editorSettings: editorSettings,
                showLineNumbers: editorSettings.showLineNumbers,
                lineWrapping: editorSettings.lineWrapping,
                themeVersion: ghostty.configVersion,
                showsVerticalScroller: true,
                focused: e.isFocused,
                searchNeedle: e.state.searchNeedle,
                searchNavigationVersion: e.state.searchNavigationVersion,
                searchNavigationDirection: e.state.searchNavigationDirection,
                searchCaseSensitive: e.state.searchCaseSensitive,
                searchUseRegex: e.state.searchUseRegex,
                replaceText: e.state.replaceText,
                replaceVersion: e.state.replaceVersion,
                replaceAllVersion: e.state.replaceAllVersion,
                editorFocusVersion: e.state.editorFocusVersion,
                onFocus: { dispatchFocus(areaID: e.areaID) }
            )
        }
    }

    private func dispatchFocus(areaID: UUID) {
        appState.dispatch(.focusArea(projectID: projectID, areaID: areaID))
    }

    private func dispatchSplit(areaID: UUID, direction: SplitDirection, position: SplitPosition) {
        appState.dispatch(.splitArea(.init(
            projectID: projectID,
            areaID: areaID,
            direction: direction,
            position: position
        )))
    }

    private func handleProcessExit(tabID: UUID, areaID: UUID) {
        guard let area = root.findArea(id: areaID),
              let tab = area.tabs.first(where: { $0.id == tabID }),
              let pane = tab.content.pane
        else { return }
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
            appState.forceCloseTab(tabID, areaID: areaID, projectID: projectID)
        }
    }
}
