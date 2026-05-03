import AppKit
import RoostHostdCore
import SwiftUI

struct TerminalPane: View {
    let state: TerminalPaneState
    let focused: Bool
    let visible: Bool
    let onFocus: () -> Void
    let onProcessExit: () -> Void
    let onSplitRequest: (SplitDirection, SplitPosition) -> Void

    @Bindable private var ownership = PaneOwnershipStore.shared
    @Environment(\.roostHostdClient) private var hostdClient
    @State private var hostdOutput = HostdOwnedTerminalOutputModel()

    private var remoteOwnerName: String? {
        if case let .remote(_, name) = ownership.owner(for: state.id) { name } else { nil }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if state.hostdRuntimeOwnership == .hostdOwnedProcess {
                HostdOwnedTerminalView(agentName: state.agentKind.displayName, output: hostdOutput)
                    .overlay {
                        HostdOwnedTerminalResizeReporter(clientAvailable: hostdClient != nil) { size in
                            Task {
                                await hostdOutput.resize(client: hostdClient, paneID: state.id, size: size)
                            }
                        }
                    }
                    .overlay {
                        HostdOwnedTerminalInputBridge(
                            focused: focused,
                            visible: visible,
                            onFocus: onFocus
                        ) { action in
                            Task {
                                switch action {
                                case let .input(data):
                                    await hostdOutput.sendInput(client: hostdClient, paneID: state.id, data: data)
                                case let .signal(signal):
                                    await hostdOutput.sendSignal(client: hostdClient, paneID: state.id, signal: signal)
                                }
                            }
                        }
                    }
                    .task(id: HostdOwnedTerminalStreamKey(
                        paneID: state.id,
                        clientAvailable: hostdClient != nil
                    )) {
                        await hostdOutput.stream(client: hostdClient, paneID: state.id)
                    }
            } else {
                TerminalBridge(
                    state: state,
                    focused: focused,
                    onFocus: onFocus,
                    onProcessExit: onProcessExit,
                    onSplitRequest: onSplitRequest
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Terminal")
                .accessibilityAddTraits(.allowsDirectInteraction)
                .opacity(remoteOwnerName == nil ? 1 : 0)
                .allowsHitTesting(remoteOwnerName == nil)
            }

            if let name = remoteOwnerName {
                RemoteControlledPlaceholder(deviceName: name) {
                    PaneOwnershipStore.shared.releaseToMac(paneID: state.id)
                }
                .transition(.opacity)
            }

            if state.searchState.isVisible {
                TerminalSearchBar(
                    searchState: state.searchState,
                    onNavigateNext: {
                        let view = TerminalViewRegistry.shared.existingView(for: state.id)
                        view?.navigateSearch(direction: .next)
                    },
                    onNavigatePrevious: {
                        let view = TerminalViewRegistry.shared.existingView(for: state.id)
                        view?.navigateSearch(direction: .previous)
                    },
                    onClose: {
                        let view = TerminalViewRegistry.shared.existingView(for: state.id)
                        view?.endSearch()
                        DispatchQueue.main.async {
                            view?.window?.makeFirstResponder(view)
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refocusActiveTerminal)) { _ in
            guard focused, visible else { return }
            let view = TerminalViewRegistry.shared.existingView(for: state.id)
            DispatchQueue.main.async {
                view?.window?.makeFirstResponder(view)
            }
        }
    }
}

private struct HostdOwnedTerminalStreamKey: Equatable {
    let paneID: UUID
    let clientAvailable: Bool
}

struct HostdOwnedTerminalView: View {
    let agentName: String
    @Bindable var output: HostdOwnedTerminalOutputModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if output.text.isEmpty {
                emptyState
            } else {
                outputScroll
            }

            statusBadge
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuxyTheme.bg)
        .accessibilityLabel("\(agentName), running in hostd")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.system(size: 28))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text(agentName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            switch output.status {
            case .waiting,
                 .streaming:
                Text("Waiting for output")
                    .font(.system(size: 12))
                    .foregroundStyle(MuxyTheme.fgMuted)
            case let .failed(message):
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(MuxyTheme.warning)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            Spacer()
        }
    }

    private var outputScroll: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                Text(output.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fg)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
                Color.clear
                    .frame(height: 1)
                    .id("hostd-output-bottom")
            }
            .onChange(of: output.text) { _, _ in
                proxy.scrollTo("hostd-output-bottom", anchor: .bottom)
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.12), in: Capsule())
        .padding(10)
    }

    private var statusLabel: String {
        switch output.status {
        case .waiting:
            "WAIT"
        case .streaming:
            "HOSTD"
        case .failed:
            "ERROR"
        }
    }

    private var statusColor: Color {
        switch output.status {
        case .waiting:
            MuxyTheme.fgMuted
        case .streaming:
            MuxyTheme.accent
        case .failed:
            MuxyTheme.warning
        }
    }
}

struct RemoteControlledPlaceholder: View {
    let deviceName: String
    let onTakeOver: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "iphone.gen3")
                .font(.system(size: 28))
                .foregroundStyle(MuxyTheme.fgMuted)
            Text("Controlled by \(deviceName)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MuxyTheme.fg)
            Text("This terminal session is currently being used on \(deviceName). Take over to resume on Mac.")
                .font(.system(size: 12))
                .foregroundStyle(MuxyTheme.fgMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                onTakeOver()
            } label: {
                HStack(spacing: 8) {
                    Text("Take Over")
                    Text("⌘↩")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .opacity(0.72)
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MuxyTheme.bg)
    }
}

struct TerminalBridge: NSViewRepresentable {
    let state: TerminalPaneState
    let focused: Bool
    let onFocus: () -> Void
    let onProcessExit: () -> Void
    let onSplitRequest: (SplitDirection, SplitPosition) -> Void
    @Environment(\.overlayActive) private var overlayActive
    @Environment(\.activeWorktreeKey) private var worktreeKey

    final class Coordinator {
        var wasFocused = false
        var wasOverlayActive = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> GhosttyTerminalNSView {
        let registry = TerminalViewRegistry.shared
        let view = registry.view(
            for: state.id,
            workingDirectory: state.currentWorkingDirectory ?? state.projectPath,
            command: state.startupCommand,
            commandInteractive: state.startupCommandInteractive
        )
        if view.envVars.isEmpty, let key = worktreeKey {
            view.envVars = TerminalPaneEnvironment.ordered(paneID: state.id, worktreeKey: key, configured: state.env)
        }
        view.isFocused = focused
        view.overlayActive = overlayActive
        view.onFocus = onFocus
        view.onProcessExit = onProcessExit
        view.onSplitRequest = onSplitRequest
        view.onTitleChange = { [weak state] title in
            DispatchQueue.main.async {
                state?.setTitle(title)
            }
        }
        view.onWorkingDirectoryChange = { [weak state] path in
            DispatchQueue.main.async {
                state?.setWorkingDirectory(path)
            }
        }
        configureSearchCallbacks(view)
        configureFileOpenCallback(view)
        context.coordinator.wasFocused = focused
        if focused, !overlayActive {
            view.notifySurfaceFocused()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                view.window?.makeFirstResponder(view)
            }
        } else {
            view.notifySurfaceUnfocused()
            if view.window?.firstResponder === view {
                view.window?.makeFirstResponder(nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: GhosttyTerminalNSView, context: Context) {
        if nsView.envVars.isEmpty, nsView.surface == nil, let key = worktreeKey {
            nsView.envVars = TerminalPaneEnvironment.ordered(paneID: state.id, worktreeKey: key, configured: state.env)
        }
        nsView.overlayActive = overlayActive
        nsView.onFocus = onFocus
        nsView.onProcessExit = onProcessExit
        nsView.onSplitRequest = onSplitRequest
        nsView.onTitleChange = { [weak state] title in
            DispatchQueue.main.async {
                state?.setTitle(title)
            }
        }
        nsView.onWorkingDirectoryChange = { [weak state] path in
            DispatchQueue.main.async {
                state?.setWorkingDirectory(path)
            }
        }
        configureSearchCallbacks(nsView)
        configureFileOpenCallback(nsView)
        let wasFocused = context.coordinator.wasFocused
        let wasOverlayActive = context.coordinator.wasOverlayActive
        context.coordinator.wasFocused = focused
        context.coordinator.wasOverlayActive = overlayActive
        nsView.isFocused = focused

        if overlayActive {
            if nsView.window?.firstResponder === nsView || nsView.window?.firstResponder === nsView.inputContext {
                nsView.window?.makeFirstResponder(nil)
            }
            if !wasOverlayActive {
                nsView.notifySurfaceUnfocused()
            }
        } else if focused, !wasFocused || wasOverlayActive {
            nsView.notifySurfaceFocused()
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else if !focused, wasFocused {
            nsView.notifySurfaceUnfocused()
        }
    }

    private func configureFileOpenCallback(_ view: GhosttyTerminalNSView) {
        let projectID = worktreeKey?.projectID
        let projectPath = state.projectPath
        view.onCmdClickFile = { token in
            guard let projectID else { return }
            guard let resolved = Self.resolveFilePath(token, projectPath: projectPath) else { return }
            Task { @MainActor in
                NotificationStore.shared.appState?.openFile(resolved, projectID: projectID, preserveFocus: true)
            }
        }
        view.resolveCmdHoverFile = { token in
            Self.resolveFilePath(token, projectPath: projectPath) != nil
        }
        view.onOpenURL = { url in
            guard let projectID, url.isFileURL else { return false }
            let path = url.path
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return false }
            Task { @MainActor in
                NotificationStore.shared.appState?.openFile(path, projectID: projectID, preserveFocus: true)
            }
            return true
        }
    }

    static func resolveFilePath(_ token: String, projectPath: String) -> String? {
        let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t\n\r()[]<>"))
        guard !cleaned.isEmpty else { return nil }
        let expanded = (cleaned as NSString).expandingTildeInPath
        let candidate: String = if expanded.hasPrefix("/") {
            expanded
        } else {
            (projectPath as NSString).appendingPathComponent(expanded)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory) else { return nil }
        guard !isDirectory.boolValue else { return nil }
        return candidate
    }

    private func configureSearchCallbacks(_ view: GhosttyTerminalNSView) {
        view.onSearchStart = { [weak state] needle in
            guard let state else { return }
            let searchState = state.searchState
            if let needle, !needle.isEmpty {
                searchState.needle = needle
            }
            searchState.isVisible = true
            searchState.focusVersion += 1
            searchState.startPublishing { [weak view] query in
                view?.sendSearchQuery(query)
            }
            if !searchState.needle.isEmpty {
                searchState.pushNeedle()
            }
        }
        view.onSearchEnd = { [weak state] in
            guard let state else { return }
            state.searchState.stopPublishing()
            state.searchState.isVisible = false
            state.searchState.needle = ""
            state.searchState.total = nil
            state.searchState.selected = nil
        }
        view.onSearchTotal = { [weak state] total in
            state?.searchState.total = total
        }
        view.onSearchSelected = { [weak state] selected in
            state?.searchState.selected = selected
        }
    }
}
