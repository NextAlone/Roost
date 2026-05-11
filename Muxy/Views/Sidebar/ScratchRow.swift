import MuxyShared
import SwiftUI

enum ScratchRowLayout {
    static let expandedOuterHorizontalInset: CGFloat = SidebarLayout.expandedProjectListHorizontalInset
    static let expandedContentLeadingInset: CGFloat = ExpandedWorktreeRowLayout.projectLeadingContentInset
    static let expandedContentTrailingInset: CGFloat = ExpandedWorktreeRowLayout.trailingContentInset
    static let expandedIconSize: CGFloat = ExpandedWorktreeRowLayout.projectIconSize
    static let expandedMinHeight: CGFloat = ExpandedWorktreeRowLayout.projectRowMinHeight
    static let expandedVerticalPadding: CGFloat = ExpandedWorktreeRowLayout.projectVerticalPadding
}

struct ScratchRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.roostHostdClient) private var hostdClient

    @State private var hovered = false

    private var isActive: Bool {
        appState.activeProjectID == Project.scratchID
    }

    private var scratchKey: WorktreeKey {
        WorktreeKey(projectID: Project.scratchID, worktreeID: Worktree.scratchID)
    }

    var body: some View {
        _ = appState.agentActivityRevision
        let summary = SidebarAgentActivityResolver.summary(
            tabs: appState.allTabs(forKey: scratchKey),
            activeTabID: isActive ? appState.focusedArea(for: Project.scratchID)?.activeTabID : nil
        )
        return HStack(spacing: ExpandedWorktreeRowLayout.projectColumnSpacing) {
            icon

            Text("Scratch")
                .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? MuxyTheme.fg : MuxyTheme.fgMuted)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let summary {
                AgentActivityDotStack(dots: summary.dots)
            }
        }
        .frame(minHeight: ScratchRowLayout.expandedMinHeight)
        .padding(.leading, ScratchRowLayout.expandedContentLeadingInset)
        .padding(.trailing, ScratchRowLayout.expandedContentTrailingInset)
        .padding(.vertical, ScratchRowLayout.expandedVerticalPadding)
        .background(headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MuxyTheme.border.opacity(0.55))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            Button("New Session…") { createSession(kind: .terminal) }
        }
        .onTapGesture { selectScratch() }
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(hovered ? MuxyTheme.hover : MuxyTheme.surface)

            Image(systemName: "doc.plaintext")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? MuxyTheme.fg : MuxyTheme.fgMuted)
        }
        .frame(
            width: ScratchRowLayout.expandedIconSize,
            height: ScratchRowLayout.expandedIconSize
        )
    }

    @ViewBuilder
    private var headerBackground: some View {
        if isActive {
            MuxyTheme.accentSoft
        } else if hovered {
            MuxyTheme.hover
        } else {
            Color.clear
        }
    }

    private func selectScratch() {
        ensureScratchWorkspace()
        appState.dispatch(.selectProject(
            projectID: Project.scratchID,
            worktreeID: Worktree.scratchID,
            worktreePath: Worktree.scratchPath
        ))
        if appState.allTabs(forKey: scratchKey).isEmpty {
            appState.createAgentTab(.terminal, projectID: Project.scratchID, hostdClient: hostdClient)
        }
    }

    private func createSession(kind: AgentKind) {
        ensureScratchWorkspace()
        appState.dispatch(.selectProject(
            projectID: Project.scratchID,
            worktreeID: Worktree.scratchID,
            worktreePath: Worktree.scratchPath
        ))
        appState.createAgentTab(kind, projectID: Project.scratchID, hostdClient: hostdClient)
    }

    private func ensureScratchWorkspace() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Worktree.scratchPath) {
            try? fm.createDirectory(atPath: Worktree.scratchPath, withIntermediateDirectories: true)
        }
        if appState.workspaceRoots[scratchKey] == nil {
            appState.dispatch(.selectProject(
                projectID: Project.scratchID,
                worktreeID: Worktree.scratchID,
                worktreePath: Worktree.scratchPath
            ))
        }
    }
}

struct ScratchCollapsedRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.roostHostdClient) private var hostdClient

    @State private var hovered = false

    private var isActive: Bool {
        appState.activeProjectID == Project.scratchID
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(hovered ? MuxyTheme.hover : MuxyTheme.surface)

            Image(systemName: "doc.plaintext")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? MuxyTheme.fg : MuxyTheme.fgMuted)
        }
        .frame(width: 28, height: 28)
        .padding(3)
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(isActive ? MuxyTheme.accent : .clear, lineWidth: 1.5)
                .animation(.easeInOut(duration: 0.15), value: isActive)
        }
        .help("Scratch")
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scratch")
        .accessibilityValue(isActive ? "Active" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
        .onHover { hovered = $0 }
        .onTapGesture { selectScratch() }
        .contextMenu {
            Button("New Session…") { createSession(kind: .terminal) }
        }
    }

    private func selectScratch() {
        ensureScratchWorkspace()
        appState.dispatch(.selectProject(
            projectID: Project.scratchID,
            worktreeID: Worktree.scratchID,
            worktreePath: Worktree.scratchPath
        ))
        let scratchKey = WorktreeKey(projectID: Project.scratchID, worktreeID: Worktree.scratchID)
        if appState.allTabs(forKey: scratchKey).isEmpty {
            appState.createAgentTab(.terminal, projectID: Project.scratchID, hostdClient: hostdClient)
        }
    }

    private func createSession(kind: AgentKind) {
        ensureScratchWorkspace()
        selectScratch()
        appState.createAgentTab(kind, projectID: Project.scratchID, hostdClient: hostdClient)
    }

    private func ensureScratchWorkspace() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Worktree.scratchPath) {
            try? fm.createDirectory(atPath: Worktree.scratchPath, withIntermediateDirectories: true)
        }
        let scratchKey = WorktreeKey(projectID: Project.scratchID, worktreeID: Worktree.scratchID)
        if appState.workspaceRoots[scratchKey] == nil {
            appState.dispatch(.selectProject(
                projectID: Project.scratchID,
                worktreeID: Worktree.scratchID,
                worktreePath: Worktree.scratchPath
            ))
        }
    }
}
