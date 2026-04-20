import SwiftUI

/// Top-level view: header + (launcher xor terminal). Owns the active
/// `LaunchedSession` state.
struct RootView: View {
    @State private var agentDraft: String = "claude"
    @State private var launched: LaunchedSession?

    private let ghosttyInfo = GhosttyInfo.current
    private let bridgeVersion = RoostBridge.version

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                ghosttyInfo: ghosttyInfo,
                bridgeVersion: bridgeVersion,
                launchedKind: launched?.spec.agentKind,
                onStop: { launched = nil }
            )
            Divider()
            content
        }
        .onReceive(NotificationCenter.default.publisher(for: .roostSurfaceClosed)) { _ in
            launched = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if let launched {
            TerminalView(
                command: launched.spec.command.isEmpty ? nil : launched.spec.command,
                workingDirectory: launched.spec.workingDirectory.isEmpty
                    ? nil : launched.spec.workingDirectory
            )
            .id(launched.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LauncherView(
                agentDraft: $agentDraft,
                onLaunch: launch
            )
        }
    }

    private func launch() {
        let spec = RoostBridge.prepareSession(agent: agentDraft)
        launched = LaunchedSession(spec: spec)
    }
}

/// One active session in the UI. Identifiable so the `.id(...)` modifier can
/// force-recreate the NSViewRepresentable on relaunch (fresh ghostty surface).
struct LaunchedSession: Identifiable {
    let id = UUID()
    let spec: SessionSpecSwift
}
