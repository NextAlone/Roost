# Phase 4d — `requiresDedicatedWorkspace` Enforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** When `AgentPreset.requiresDedicatedWorkspace == true`, opening an agent tab routes through the existing `CreateWorktreeSheet` flow instead of creating the tab in the active workspace. After the user creates the new workspace, the agent tab opens inside it.

**Architecture:** Notification-based. `ShortcutActionDispatcher.performAgentTab` consults the preset; if the flag is true, it posts `.requestCreateWorkspaceForAgent` (carrying the AgentKind in userInfo). Sidebar rows (`ExpandedProjectRow`, `ProjectRow`) listen and present `CreateWorktreeSheet` with a `pendingAgentKind`. Their existing `handleCreateWorktreeResult` checks the pending kind and, if set, activates the new worktree + creates an agent tab inside it.

**Tech Stack:** Swift 6, SwiftUI, swift-testing, NotificationCenter.

**Locked decisions:**
- All built-in presets keep `requiresDedicatedWorkspace == false`. Phase 4d only adds the routing scaffold; flipping any preset to true is a separate product decision (Phase 7 user-configurable presets).
- Routing path: dispatcher → notification → sidebar → CreateWorktreeSheet → on success → activate new workspace → createAgentTab.
- Notification posts the agent kind via `userInfo["kind"]` (raw value, not enum directly — Notification requires `[AnyHashable: Any]`).
- Test surface: a pure helper `ShortcutActionDispatcher.shouldRouteToWorkspaceCreation(kind:presetLookup:)` for easy unit testing without mocking NotificationCenter.

**Out of scope:**
- Changing any built-in preset's flag.
- Auto-creating workspaces silently (always go through CreateWorktreeSheet for user control).
- Cancelling the routing if the user cancels the sheet — sidebar simply discards `pendingAgentKind`. Falling back to "open in current workspace" would surprise the user.

---

## File Structure

**Create:**
- `Tests/MuxyTests/Services/ShortcutActionDispatcherDedicatedWorkspaceTests.swift`

**Modify:**
- `Muxy/Services/Notification+Names.swift` — add `.requestCreateWorkspaceForAgent`
- `Muxy/Services/ShortcutActionDispatcher.swift` — branch `performAgentTab` on preset flag; extract pure helper
- `Muxy/Views/Sidebar/ExpandedProjectRow.swift` — listen to notification + thread `pendingAgentKind` through `handleCreateWorktreeResult`
- `Muxy/Views/Sidebar/ProjectRow.swift` — same pattern as ExpandedProjectRow

---

## Task 1: Notification name

**Files:**
- Modify: `Muxy/Services/Notification+Names.swift` (or wherever `Notification.Name` extensions live — search if uncertain)

- [ ] **Step 1: Locate the file**

```bash
grep -rn "extension Notification.Name" Muxy/ --include="*.swift" | head -3
```

- [ ] **Step 2: Add a new name**

In the appropriate file, add to the existing `extension Notification.Name`:

```swift
    static let requestCreateWorkspaceForAgent = Notification.Name("muxy.requestCreateWorkspaceForAgent")
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```

Expected SUCCESS.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(notify): add requestCreateWorkspaceForAgent notification name"
```

---

## Task 2: Dispatcher routes flag-bearing presets via notification

**Files:**
- Modify: `Muxy/Services/ShortcutActionDispatcher.swift`
- Test: `Tests/MuxyTests/Services/ShortcutActionDispatcherDedicatedWorkspaceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MuxyTests/Services/ShortcutActionDispatcherDedicatedWorkspaceTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("ShortcutActionDispatcher dedicated workspace routing")
struct ShortcutActionDispatcherDedicatedWorkspaceTests {
    @Test("routes when preset.requiresDedicatedWorkspace == true")
    func routesWhenFlagTrue() {
        let lookup: (AgentKind) -> AgentPreset = { _ in
            AgentPreset(kind: .claudeCode, defaultCommand: "claude", requiresDedicatedWorkspace: true)
        }
        #expect(
            ShortcutActionDispatcher.shouldRouteToWorkspaceCreation(
                kind: .claudeCode,
                presetLookup: lookup
            )
        )
    }

    @Test("does not route when flag false")
    func staysWhenFlagFalse() {
        let lookup: (AgentKind) -> AgentPreset = { kind in
            AgentPreset(kind: kind, defaultCommand: "claude", requiresDedicatedWorkspace: false)
        }
        #expect(
            !ShortcutActionDispatcher.shouldRouteToWorkspaceCreation(
                kind: .claudeCode,
                presetLookup: lookup
            )
        )
    }
}
```

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter ShortcutActionDispatcherDedicatedWorkspaceTests
```

Expected FAIL — `shouldRouteToWorkspaceCreation` not in scope.

- [ ] **Step 3: Add helper + branch logic**

In `Muxy/Services/ShortcutActionDispatcher.swift`:

1. Add this static helper (place near the top of the struct or just above `private func performAgentTab`):

```swift
    static func shouldRouteToWorkspaceCreation(
        kind: AgentKind,
        presetLookup: (AgentKind) -> AgentPreset = AgentPresetCatalog.preset(for:)
    ) -> Bool {
        presetLookup(kind).requiresDedicatedWorkspace
    }
```

2. Modify `performAgentTab` (around line 185) to branch on the flag:

```swift
    private func performAgentTab(_ kind: AgentKind) -> Bool {
        guard let projectID = appState.activeProjectID else { return false }
        if Self.shouldRouteToWorkspaceCreation(kind: kind) {
            notificationCenter.post(
                name: .requestCreateWorkspaceForAgent,
                object: nil,
                userInfo: ["kind": kind.rawValue]
            )
            return true
        }
        if appState.workspaceRoot(for: projectID) == nil {
            guard let worktree = resolveActiveWorktree(for: projectID) else { return false }
            appState.selectWorktree(projectID: projectID, worktree: worktree)
        }
        appState.createAgentTab(kind, projectID: projectID)
        return true
    }
```

- [ ] **Step 4: Run targeted + full suite**

```bash
swift test --filter ShortcutActionDispatcherDedicatedWorkspaceTests
swift test 2>&1 | tail -3
```

Expected: 2 new tests pass; total all green.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(dispatcher): route to workspace creation when preset requires dedicated"
```

---

## Task 3: Sidebar listens + threads pendingAgentKind

**Files:**
- Modify: `Muxy/Views/Sidebar/ExpandedProjectRow.swift`
- Modify: `Muxy/Views/Sidebar/ProjectRow.swift`

- [ ] **Step 1: ExpandedProjectRow — add pendingAgentKind state**

In `Muxy/Views/Sidebar/ExpandedProjectRow.swift`:

1. Find existing `@State` declarations near the top. Add:

```swift
    @State private var pendingAgentKind: AgentKind?
```

2. Find the `.sheet(isPresented: $showCreateWorktreeSheet)` block (around line 91-96). Locate the `handleCreateWorktreeResult(result)` invocation in its `onFinish` — that's where we need the pendingAgentKind to flow.

3. Modify the existing `handleCreateWorktreeResult` (find by grep) to handle `.created` with a pending agent kind. The current implementation likely handles things like running setup commands. Add a branch:

```swift
    private func handleCreateWorktreeResult(_ result: CreateWorktreeResult) {
        let pending = pendingAgentKind
        pendingAgentKind = nil
        switch result {
        case let .created(worktree, runSetup):
            appState.selectWorktree(projectID: project.id, worktree: worktree)
            if let pending {
                appState.createAgentTab(pending, projectID: project.id)
            }
            // Existing behavior continues — preserve whatever the original handler did with runSetup, e.g. running setup commands.
            // If the original method has more lines, keep them after this block.
            // If runSetup logic exists, it should still apply.
        case .cancelled:
            break
        }
    }
```

Read the actual `handleCreateWorktreeResult` first and ADD the new lines without removing existing logic. The pattern is: capture pending, clear it, then in the .created branch, activate worktree and (if pending non-nil) create agent tab. Existing setup-commands logic must remain intact.

4. Add an `.onReceive` observer on a top-level view modifier in the body. Find where other `.sheet` / `.popover` modifiers chain (around line 91). Add right alongside them:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .requestCreateWorkspaceForAgent)) { note in
            guard appState.activeProjectID == project.id,
                  let raw = note.userInfo?["kind"] as? String,
                  let kind = AgentKind(rawValue: raw)
            else { return }
            pendingAgentKind = kind
            showCreateWorktreeSheet = true
        }
```

The guard ensures only the active project's row reacts.

- [ ] **Step 2: ProjectRow — same pattern**

Apply the same three changes to `Muxy/Views/Sidebar/ProjectRow.swift`:
- Add `@State private var pendingAgentKind: AgentKind?`
- Modify `handleCreateWorktreeResult` (or equivalent) to thread pendingAgentKind
- Add the `.onReceive` observer with the same active-project guard

If `ProjectRow` doesn't have an existing `handleCreateWorktreeResult`, find how its `.sheet`'s `onFinish` is currently handled and add the pendingAgentKind logic in the same place.

- [ ] **Step 3: Build + test + manual smoke**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -3
```

Expected: SUCCESS, all green.

Manual smoke: edit `MuxyShared/Agent/AgentPreset.swift` temporarily to flip `claudeCode`'s flag to `true` (DO NOT COMMIT THIS), run `swift run Muxy`, trigger "New Claude Code Tab" via menu — sheet should open. Cancel without creating: nothing happens. Create: new workspace created + Claude Code tab opens in it. Then revert the flag and re-run tests.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(sidebar): listen for dedicated-workspace agent requests"
```

---

## Task 4: Migration plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append Phase 4d note**

After the Phase 4c status block in the Phase 4 section, append:

```markdown
**Status (2026-04-28): Phase 4d (`requiresDedicatedWorkspace` enforcement) landed.**

- `ShortcutActionDispatcher.shouldRouteToWorkspaceCreation(kind:presetLookup:)` exposes the routing decision as a pure helper for testing.
- When `AgentPreset.requiresDedicatedWorkspace == true`, `performAgentTab` posts `.requestCreateWorkspaceForAgent` (carrying `kind.rawValue` in userInfo) instead of creating the tab in the active workspace.
- Sidebar rows (`ExpandedProjectRow`, `ProjectRow`) observe the notification, store `pendingAgentKind`, and present `CreateWorktreeSheet`. On successful workspace creation, the new workspace is activated and an agent tab of the pending kind is opened inside it.
- All built-in presets remain `requiresDedicatedWorkspace = false` — Phase 4d adds the routing scaffold without changing default UX. User-configurable presets land in Phase 7.
- **Phase 4 complete.** Phase 4c.5 (session lifecycle state badges) remains as an optional follow-up requiring GhosttyTerminalNSView lifecycle hooks.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(plan): mark Phase 4d (dedicated workspace routing) landed"
```

---

## Self-Review Checklist

- [ ] All built-in presets still `requiresDedicatedWorkspace = false`.
- [ ] No changes to `AgentKind` / `AgentPreset` / `AgentPresetCatalog`.
- [ ] No comments added.
- [ ] Build + test green.
- [ ] Existing `handleCreateWorktreeResult` logic preserved (setup commands etc.).
- [ ] `.onReceive` observers guard against firing for inactive projects.
