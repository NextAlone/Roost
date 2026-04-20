import SwiftUI

/// Top-level view. Owns the session list and which tab is active. When no
/// sessions are open, the entire window shows the launcher; otherwise the
/// window is tab row + active terminal, and the launcher opens as a sheet.
struct RootView: View {
    @State private var agentDraft: String = "claude"
    @State private var sessions: [LaunchedSession] = []
    @State private var selectedID: LaunchedSession.ID?
    @State private var isShowingLauncher: Bool = false

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
                agentDraft: $agentDraft,
                onLaunch: { launchFromSheet() },
                onCancel: { isShowingLauncher = false }
            )
        }
    }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        if sessions.isEmpty {
            LauncherView(
                agentDraft: $agentDraft,
                onLaunch: { launchDirect() }
            )
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

    // MARK: Actions

    private func launchDirect() {
        let session = makeSession()
        sessions.append(session)
        selectedID = session.id
    }

    private func launchFromSheet() {
        let session = makeSession()
        sessions.append(session)
        selectedID = session.id
        isShowingLauncher = false
    }

    private func makeSession() -> LaunchedSession {
        let spec = RoostBridge.prepareSession(agent: agentDraft)
        return LaunchedSession(spec: spec)
    }

    private func closeSession(id: LaunchedSession.ID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions.remove(at: idx)

        guard !sessions.isEmpty else {
            selectedID = nil
            return
        }

        if selectedID == id {
            // Keep selection near the removed tab.
            selectedID = sessions[min(idx, sessions.count - 1)].id
        }
    }
}

/// One active session in the UI. `Identifiable` so the `.id(...)` modifier on
/// `TerminalView` force-recreates the NSViewRepresentable on relaunch.
struct LaunchedSession: Identifiable, Equatable {
    let id: UUID
    let spec: SessionSpecSwift

    init(id: UUID = UUID(), spec: SessionSpecSwift) {
        self.id = id
        self.spec = spec
    }
}
