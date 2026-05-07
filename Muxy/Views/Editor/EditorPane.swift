import SwiftUI

struct EditorPane: View {
    @Bindable var state: EditorTabState
    let focused: Bool
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EditorBreadcrumb(state: state)
            Rectangle().fill(MuxyTheme.border).frame(height: 1)
            if state.awaitingLargeFileConfirmation {
                largeFileConfirmation.background(MuxyTheme.bg)
            } else if state.isLoading {
                loadingView.background(MuxyTheme.bg)
            } else if let error = state.errorMessage {
                errorView(error).background(MuxyTheme.bg)
            } else {
                editorContentLayer
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInTerminal)) { _ in
            guard focused else { return }
            if state.isMarkdownFile, state.markdownViewMode == .preview {
                state.markdownViewMode = .code
            }
            if !state.currentSelection.isEmpty {
                state.searchNeedle = state.currentSelection
            }
            state.searchVisible = true
            state.searchFocusVersion += 1
        }
    }

    private var editorContentLayer: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear.allowsHitTesting(false)

            if state.isIncrementalLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading full file...")
                        .font(.system(size: 11))
                        .foregroundStyle(MuxyTheme.fgMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(MuxyTheme.bg.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(MuxyTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.top, 6)
                .padding(.trailing, state.searchVisible && showsCodeEditor ? 260 : 8)
            }

            if state.searchVisible, showsCodeEditor {
                EditorSearchBar(
                    state: state,
                    onNext: {
                        state.navigateSearch(.next)
                    },
                    onPrevious: {
                        state.navigateSearch(.previous)
                    },
                    onReplace: {
                        state.requestReplaceCurrent()
                    },
                    onReplaceAll: {
                        state.requestReplaceAll()
                    },
                    onClose: {
                        state.searchVisible = false
                        state.editorFocusVersion += 1
                    }
                )
            }
        }
    }

    private var showsCodeEditor: Bool {
        !state.isMarkdownFile || state.markdownViewMode != .preview
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
    }

    private var largeFileConfirmation: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text("Large File")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Text("This file is \(formattedLargeFileSize). Large files may slow down the editor.")
                .font(.system(size: 12))
                .foregroundStyle(MuxyTheme.fgMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 8) {
                Button("Cancel") {
                    state.cancelLargeFileOpen()
                }
                .keyboardShortcut(.cancelAction)
                Button("Open Anyway") {
                    state.confirmLargeFileOpen()
                }
                .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var formattedLargeFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: state.largeFileSize)
    }

    private func errorView(_ error: String) -> some View {
        VStack {
            Spacer()
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(MuxyTheme.diffRemoveFg)
            Spacer()
        }
    }
}

struct MarkdownPaneContent: View {
    @Bindable var state: EditorTabState
    let focused: Bool
    let onFocus: () -> Void
    @Environment(GhosttyService.self) private var ghostty
    @State private var editorSettings = EditorSettings.shared
    @FocusState private var markdownPreviewFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let codeWidth = max(0, codeFraction * geo.size.width)
            let previewWidth = max(0, geo.size.width - codeWidth)
            ZStack(alignment: .topLeading) {
                CodeEditorView(
                    state: state,
                    editorSettings: editorSettings,
                    showLineNumbers: editorSettings.showLineNumbers,
                    lineWrapping: editorSettings.lineWrapping,
                    themeVersion: ghostty.configVersion,
                    showsVerticalScroller: true,
                    focused: focused && state.markdownViewMode != .preview,
                    searchNeedle: state.searchNeedle,
                    searchNavigationVersion: state.searchNavigationVersion,
                    searchNavigationDirection: state.searchNavigationDirection,
                    searchCaseSensitive: state.searchCaseSensitive,
                    searchUseRegex: state.searchUseRegex,
                    replaceText: state.replaceText,
                    replaceVersion: state.replaceVersion,
                    replaceAllVersion: state.replaceAllVersion,
                    editorFocusVersion: state.editorFocusVersion,
                    onFocus: onFocus
                )
                .frame(width: codeWidth, height: geo.size.height)
                .opacity(showsCode ? 1 : 0)
                .allowsHitTesting(showsCode)

                markdownPreview
                    .frame(width: previewWidth, height: geo.size.height)
                    .offset(x: codeWidth, y: 0)
                    .opacity(showsPreview ? 1 : 0)
                    .allowsHitTesting(showsPreview)
            }
        }
    }

    private var codeFraction: CGFloat {
        switch state.markdownViewMode {
        case .code: return 1
        case .preview: return 0
        case .split: return 0.5
        }
    }

    private var showsCode: Bool {
        state.markdownViewMode != .preview
    }

    private var showsPreview: Bool {
        state.markdownViewMode != .code
    }

    @ViewBuilder
    private var markdownPreview: some View {
        if shouldDelayMarkdownPreview {
            markdownPreviewLoadingView
        } else {
            MarkdownWebView(
                html: renderedMarkdownHTML,
                content: renderedMarkdownContent,
                filePath: state.filePath,
                palette: markdownPalette,
                syncScrollRequest: $state.markdownPreviewScrollRequest,
                syncScrollRequestVersion: state.markdownPreviewScrollRequestVersion,
                scrollSyncEnabled: usesMarkdownAnchorSync,
                onScrollReport: { report in
                    state.markdownPreviewMaxScrollTop = report.maxScrollTop
                    state.markdownPreviewViewportHeight = report.clientHeight
                    let map = state.currentMarkdownSyncMap()
                    let output = state.markdownSyncCoordinator.previewDidScroll(scrollTop: report.scrollTop, map: map)
                    state.applyMarkdownSyncOutput(output)
                },
                onLayoutChanged: {
                    let map = state.currentMarkdownSyncMap()
                    let output = state.markdownSyncCoordinator.reissueAfterRelayout(map: map)
                    state.applyMarkdownSyncOutput(output)
                },
                onAnchorGeometryChanged: { geometries in
                    state.markdownPreviewGeometries = geometries
                }
            )
            .background(Color(nsColor: markdownPalette.background))
            .focusable(focused)
            .focusEffectDisabled()
            .focused($markdownPreviewFocused)
            .onKeyPress(keys: ["e"]) { press in
                guard state.markdownViewMode == .preview else { return .ignored }
                let disallowed: EventModifiers = [.command, .control, .option]
                guard press.modifiers.isDisjoint(with: disallowed) else { return .ignored }
                state.markdownViewMode = press.modifiers.contains(.shift) ? .split : .code
                return .handled
            }
            .onAppear { acquireMarkdownPreviewFocusIfNeeded() }
            .onChange(of: focused) { _, _ in acquireMarkdownPreviewFocusIfNeeded() }
            .onChange(of: state.markdownViewMode) { _, _ in acquireMarkdownPreviewFocusIfNeeded() }
        }
    }

    private func acquireMarkdownPreviewFocusIfNeeded() {
        guard focused, state.isMarkdownFile, state.markdownViewMode == .preview else { return }
        if state.suppressInitialFocus {
            state.suppressInitialFocus = false
            return
        }
        markdownPreviewFocused = true
    }

    private var renderedMarkdownContent: String {
        _ = state.previewRefreshVersion
        return state.backingStore?.fullText() ?? ""
    }

    private var renderedMarkdownHTML: String {
        MarkdownRenderer.html(filePath: state.filePath)
    }

    private var markdownPalette: MarkdownRenderer.Palette {
        let palette = EditorThemePalette.active
        return MarkdownRenderer.Palette(
            background: palette.background,
            foreground: palette.foreground,
            accent: palette.accent,
            fontFamilyCSS: editorSettings.resolvedMarkdownPreviewFontFamilyCSS,
            fontScale: editorSettings.markdownPreviewFontScale
        )
    }

    private var usesMarkdownAnchorSync: Bool {
        state.markdownViewMode == .split && state.markdownScrollSyncEnabled && !shouldDelayMarkdownPreview
    }

    private var shouldDelayMarkdownPreview: Bool {
        state.isMarkdownFile && state.isIncrementalLoading
    }

    private var markdownPreviewLoadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading full markdown preview...")
                .font(.system(size: 12))
                .foregroundStyle(MuxyTheme.fgMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuxyTheme.bg)
    }
}

private struct EditorMarkdownModePicker: View {
    @Binding var mode: EditorMarkdownViewMode
    @Binding var scrollSyncEnabled: Bool

    var body: some View {
        HStack(spacing: 2) {
            if mode == .split {
                Button {
                    scrollSyncEnabled.toggle()
                } label: {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(scrollSyncEnabled ? MuxyTheme.accent : MuxyTheme.fg)
                        .frame(width: 22, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(scrollSyncEnabled ? MuxyTheme.surface : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(scrollSyncEnabled ? "Disable Scroll Sync" : "Enable Scroll Sync")
                .accessibilityLabel(scrollSyncEnabled ? "Disable Markdown Scroll Sync" : "Enable Markdown Scroll Sync")

                Rectangle()
                    .fill(MuxyTheme.border)
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 2)
            }
            ForEach(EditorMarkdownViewMode.allCases, id: \.self) { candidate in
                Button {
                    mode = candidate
                } label: {
                    Image(systemName: candidate.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 22, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(mode == candidate ? MuxyTheme.surface : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(helpText(for: candidate, currentMode: mode))
                .accessibilityLabel("Markdown \(candidate.title) View")
            }
        }
        .padding(2)
        .background(MuxyTheme.bg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(MuxyTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func helpText(for candidate: EditorMarkdownViewMode, currentMode: EditorMarkdownViewMode) -> String {
        guard currentMode == .preview else { return candidate.title }
        switch candidate {
        case .code: return "\(candidate.title) (E)"
        case .split: return "\(candidate.title) (⇧E)"
        case .preview: return candidate.title
        }
    }
}

private struct EditorBreadcrumb: View {
    @Bindable var state: EditorTabState

    private var relativePath: String {
        let full = state.filePath
        let base = state.projectPath
        guard full.hasPrefix(base) else { return state.fileName }
        var rel = String(full.dropFirst(base.count))
        if rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
        return rel
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(MuxyTheme.fgDim)
            Text(relativePath)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if state.isModified {
                Circle()
                    .fill(MuxyTheme.fg)
                    .frame(width: 6, height: 6)
            }
            if state.isReadOnly {
                Label("Read-only", systemImage: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MuxyTheme.diffHunkFg)
            }
            Spacer()
            if state.isMarkdownFile {
                EditorMarkdownModePicker(
                    mode: $state.markdownViewMode,
                    scrollSyncEnabled: $state.markdownScrollSyncEnabled
                )
                .padding(.trailing, 6)
            }
            Text("Ln \(state.cursorLine), Col \(state.cursorColumn)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MuxyTheme.fgDim)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(MuxyTheme.bg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(breadcrumbAccessibilityLabel)
    }

    private var breadcrumbAccessibilityLabel: String {
        var label = relativePath
        if state.isModified { label += ", modified" }
        if state.isReadOnly { label += ", read-only" }
        label += ", Line \(state.cursorLine), Column \(state.cursorColumn)"
        return label
    }
}
