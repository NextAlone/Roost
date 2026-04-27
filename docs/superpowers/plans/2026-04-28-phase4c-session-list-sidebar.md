# Phase 4c — Session List Under Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Render a list of sessions (terminal tabs) under each workspace row in the sidebar. Clicking a session activates that workspace + selects that tab. Show agent kind icon next to session title.

**Architecture:** Add `appState.allTabs(forKey:)` helper. Build a `SessionRow` view that takes a `TerminalTab` + `WorktreeKey`. Modify `ExpandedProjectRow` to expand a sessions sub-list under each `ExpandedWorktreeRow` when the worktree is expanded. Click → dispatch `selectWorktree` + `selectTab(tabID)`.

**Tech Stack:** Swift 6, SwiftUI, swift-testing.

**Locked decisions:**
- Sessions = `TerminalTab` instances across all `TabArea`s in a worktree's `SplitNode` tree. Iterating uses `workspaceRoots[key]?.allAreas().flatMap(\.tabs)`.
- Agent kind icon: SF Symbol per kind (terminal=`terminal`, claudeCode=`sparkles`, codex=`brain`, geminiCli=`star.circle`, openCode=`hammer`).
- Session is shown for ALL workspace rows that are *currently expanded*. Per-workspace expansion state lives in `ExpandedProjectRow` view state (no persistence).
- Click on a session ROW: if it's not the active workspace, switch to it; then select the tab.
- "Last known state" lifecycle (running / idle / exited / errored) is OUT OF SCOPE — defer to Phase 4c.5 (separate plan) since it requires GhosttyTerminalNSView lifecycle hooks.

**Out of scope:**
- Session running/idle/exited badges.
- Drag-reorder sessions in sidebar.
- Cross-workspace session list (only per-workspace).
- Persistence of expansion state.

---

## File Structure

**Create:**
- `Muxy/Views/Sidebar/SessionRow.swift`
- `Tests/MuxyTests/Models/AppStateAllTabsTests.swift`

**Modify:**
- `Muxy/Models/AppState.swift` — add `allTabs(forKey:)`
- `Muxy/Views/Sidebar/ExpandedProjectRow.swift` — render sessions under expanded worktrees
- (Possibly) `MuxyShared/Agent/AgentKind.swift` — add `var iconSystemName: String`

---

## Task 1: AgentKind icon helper

**Files:**
- Modify: `MuxyShared/Agent/AgentKind.swift`
- Test: `Tests/MuxyTests/Agent/AgentKindTests.swift` (append)

- [ ] **Step 1: Append test**

```swift
    @Test("iconSystemName is non-empty for all cases")
    func iconNonEmpty() {
        for kind in AgentKind.allCases {
            #expect(!kind.iconSystemName.isEmpty)
        }
    }

    @Test("icon mapping matches expected SF Symbols")
    func iconMapping() {
        #expect(AgentKind.terminal.iconSystemName == "terminal")
        #expect(AgentKind.claudeCode.iconSystemName == "sparkles")
        #expect(AgentKind.codex.iconSystemName == "brain")
        #expect(AgentKind.geminiCli.iconSystemName == "star.circle")
        #expect(AgentKind.openCode.iconSystemName == "hammer")
    }
```

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter AgentKindTests
```

- [ ] **Step 3: Add the property**

In `MuxyShared/Agent/AgentKind.swift`, after `displayName`, add:

```swift
    public var iconSystemName: String {
        switch self {
        case .terminal: "terminal"
        case .claudeCode: "sparkles"
        case .codex: "brain"
        case .geminiCli: "star.circle"
        case .openCode: "hammer"
        }
    }
```

- [ ] **Step 4: Run, expect pass**

```bash
swift test --filter AgentKindTests
```

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(agent): AgentKind.iconSystemName for sidebar rendering"
```

---

## Task 2: AppState.allTabs(forKey:) helper

**Files:**
- Modify: `Muxy/Models/AppState.swift`
- Test: `Tests/MuxyTests/Models/AppStateAllTabsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("AppState.allTabs(forKey:)")
struct AppStateAllTabsTests {
    @Test("returns empty for missing key")
    func missingKey() {
        let appState = AppState(
            selectionStore: SelectionStoreStub(),
            terminalViews: TerminalViewRemovingStub(),
            workspacePersistence: WorkspacePersistenceStub()
        )
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        #expect(appState.allTabs(forKey: key).isEmpty)
    }

    @Test("returns flat list across all areas")
    func flatList() {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let appState = AppState(
            selectionStore: SelectionStoreStub(),
            terminalViews: TerminalViewRemovingStub(),
            workspacePersistence: WorkspacePersistenceStub()
        )
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        area.createAgentTab(kind: .codex)
        appState.workspaceRoots[key] = .tabArea(area)
        let tabs = appState.allTabs(forKey: key)
        #expect(tabs.count == 3)
        #expect(tabs.contains { $0.content.pane?.agentKind == .claudeCode })
        #expect(tabs.contains { $0.content.pane?.agentKind == .codex })
    }
}
```

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter AppStateAllTabsTests
```

- [ ] **Step 3: Implement**

In `Muxy/Models/AppState.swift`, near `allAreas(for:)` (around line 188), add:

```swift
    func allTabs(forKey key: WorktreeKey) -> [TerminalTab] {
        guard let root = workspaceRoots[key] else { return [] }
        return root.allAreas().flatMap(\.tabs)
    }
```

- [ ] **Step 4: Run, expect 2 pass**

```bash
swift test --filter AppStateAllTabsTests
swift test 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(app): AppState.allTabs(forKey:) flattens worktree's tabs"
```

---

## Task 3: SessionRow view

**Files:**
- Create: `Muxy/Views/Sidebar/SessionRow.swift`

- [ ] **Step 1: Implement**

Create `Muxy/Views/Sidebar/SessionRow.swift`:

```swift
import MuxyShared
import SwiftUI

struct SessionRow: View {
    let tab: TerminalTab
    let isActive: Bool
    let onSelect: () -> Void

    @State private var hovered = false

    private var agentKind: AgentKind {
        tab.content.pane?.agentKind ?? .terminal
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: agentKind.iconSystemName)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? MuxyTheme.accent : MuxyTheme.fgDim)
                    .frame(width: 12)

                Text(tab.title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? MuxyTheme.fg : MuxyTheme.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(agentKind.displayName): \(tab.title)")
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isActive {
            MuxyTheme.accentSoft
        } else if hovered {
            MuxyTheme.hover
        } else {
            Color.clear
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected SUCCESS.

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(sidebar): SessionRow view with agent kind icon"
```

No tests for this view — UI-only; verified by Task 4 wiring + manual smoke.

---

## Task 4: Wire SessionRow into ExpandedProjectRow

**Files:**
- Modify: `Muxy/Views/Sidebar/ExpandedProjectRow.swift`

- [ ] **Step 1: Inspect existing layout**

Read `Muxy/Views/Sidebar/ExpandedProjectRow.swift`. Find the `ForEach(worktrees)` block (around line 233) where `ExpandedWorktreeRow` is rendered. The session list should appear underneath the row when the worktree's expansion state is open.

The plan: add a `@State private var expandedWorktreeIDs: Set<UUID>` to `ExpandedProjectRow` (or wherever `worktrees` ForEach lives). Each `ExpandedWorktreeRow` gets a chevron-style toggle (or use existing chevron if present); on toggle, add/remove worktreeID from the set. When set, render sessions list right below.

- [ ] **Step 2: Add expansion state + render sessions**

In the parent view that contains `ForEach(worktrees) { worktree in ExpandedWorktreeRow(...) }`:

1. Add `@State private var expandedWorktreeIDs: Set<UUID> = []`.

2. Wrap the existing `ExpandedWorktreeRow` call in a `VStack(alignment: .leading, spacing: 0)`:

```swift
ForEach(worktrees) { worktree in
    VStack(alignment: .leading, spacing: 0) {
        ExpandedWorktreeRow(
            projectID: project.id,
            worktree: worktree,
            // ... existing args
        )
        .onTapGesture(count: 2) {
            toggleExpansion(worktree.id)
        }

        if expandedWorktreeIDs.contains(worktree.id) {
            sessionsView(for: worktree)
        }
    }
}
```

(Read the actual file first to find the precise call site and existing args. Don't break existing behavior — only add the wrap + condition.)

3. Add helpers near the bottom of the struct:

```swift
    private func toggleExpansion(_ id: UUID) {
        if expandedWorktreeIDs.contains(id) {
            expandedWorktreeIDs.remove(id)
        } else {
            expandedWorktreeIDs.insert(id)
        }
    }

    @ViewBuilder
    private func sessionsView(for worktree: Worktree) -> some View {
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
                        onSelect: { selectSession(tab: tab, worktree: worktree) }
                    )
                    .padding(.leading, 16)
                }
            }
        }
    }

    private func isSessionActive(tab: TerminalTab, key: WorktreeKey) -> Bool {
        appState.activeWorktreeKey(for: project.id) == key
            && appState.focusedArea(for: project.id)?.activeTabID == tab.id
    }

    private func selectSession(tab: TerminalTab, worktree: Worktree) {
        appState.selectWorktree(projectID: project.id, worktree: worktree)
        if let area = appState.focusedArea(for: project.id) {
            area.selectTab(tab.id)
        }
    }
```

If `appState.activeWorktreeKey(for:)` doesn't exist (it's referenced by `focusedArea(for:)` in AppState.swift around line 155 — verify), use `appState.activeWorktreeID[project.id]` and construct the key inline.

- [ ] **Step 3: Build + test**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -3
```

Expected: SUCCESS, all tests green.

Manual smoke: `swift run Muxy`, open a project, create a Claude Code tab, double-click the workspace row in sidebar — should reveal a session list with the Claude Code tab; click another tab in that list — sidebar marks it active.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(sidebar): expandable session list under workspace rows"
```

---

## Task 5: Migration plan note + close-out

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append Phase 4c note**

After the existing Phase 4b status block in the Phase 4 section, append:

```markdown
**Status (2026-04-28): Phase 4c (session list) landed.**

- Sidebar workspace rows are now double-click expandable to reveal their sessions.
- Each session shows an SF Symbol icon per `AgentKind` (`terminal`, `sparkles`, `brain`, `star.circle`, `hammer`) plus the tab title.
- Clicking a session row activates that workspace and selects that tab.
- `AppState.allTabs(forKey:)` flattens a workspace's tabs across split panes.
- Session lifecycle state (running / idle / exited / errored) **deferred** to a Phase 4c.5 follow-up (requires GhosttyTerminalNSView lifecycle hooks). Not blocking Phase 4d.
- Phase 4d (`requiresDedicatedWorkspace` enforcement) → upcoming.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(plan): mark Phase 4c (session list) landed"
```

---

## Self-Review Checklist

- [ ] All build + test runs green.
- [ ] No comments added to source files.
- [ ] Existing `ExpandedWorktreeRow` behavior preserved (selection, rename, remove all still work).
- [ ] No type rename, no persistence change.
- [ ] Lifecycle state explicitly deferred and noted in plan.
