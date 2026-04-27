# Phase 4a — UI Relabel (Worktree → Workspace) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Relabel all user-visible "Worktree" / "worktree" strings to "Workspace" / "workspace" to align with Roost's jj-first product positioning. Internal model names and persistence keys stay unchanged.

**Architecture:** Wholesale string rename in views/commands/menus. No conditional rendering by VcsKind — Roost is jj-first and "Workspace" is acceptable umbrella terminology for git projects too. File paths (`.muxy/worktree.json`) and UserDefaults keys remain (backward compatibility).

**Tech Stack:** SwiftUI, AppKit `NSAlert`, swift-testing.

**Locked decisions:**
- Wholesale rename to "Workspace" — no per-VcsKind branching.
- Internal type names (`Worktree`, `WorktreeStore`, `WorktreeKey`, `WorktreeDTO`, `WorktreeConfig`) stay.
- File paths (`.muxy/worktree.json`, on-disk worktree directory) stay.
- UserDefaults keys (`muxy.general.autoExpandWorktreesOnProjectSwitch`, etc.) stay — only displayed labels change.
- Action enum cases (`.switchWorktree`) stay — only `displayName` changes.
- `WorktreeSwitcherOverlay` (cross-project switcher) is renamed in displayed strings only; type name stays.

**Out of scope:**
- Renaming any Swift identifier (type, function, property).
- Renaming any file or directory.
- Migrating UserDefaults keys.
- Behavioral changes (only string substitutions).

---

## File Structure

**Modify (user-visible strings only):**
- `Muxy/Views/Sidebar/WorktreePopover.swift`
- `Muxy/Views/Sidebar/ProjectRow.swift`
- `Muxy/Views/Sidebar/ExpandedProjectRow.swift`
- `Muxy/Views/Sidebar/CreateWorktreeSheet.swift`
- `Muxy/Views/Sidebar/WorktreeRefreshHelper.swift`
- `Muxy/Views/Settings/GeneralSettingsView.swift`
- `Muxy/Views/Components/WorktreeSwitcherOverlay.swift`
- `Muxy/Models/KeyBinding.swift` (only `displayName` for `.switchWorktree`)
- `Muxy/Commands/MuxyCommands.swift` (menu item "Switch Worktree...")

Plus migration plan note.

---

## Task 1: Sidebar popover relabel

**Files:**
- Modify: `Muxy/Views/Sidebar/WorktreePopover.swift`

- [ ] **Step 1: Apply substitutions**

In `Muxy/Views/Sidebar/WorktreePopover.swift`, change the following user-visible strings (use Edit tool with each `old_string` exactly as shown to keep edits unambiguous):

| Old | New |
|-----|-----|
| `"Search worktrees…"` | `"Search workspaces…"` |
| `"Refresh Worktrees"` | `"Refresh Workspaces"` |
| `"New Worktree…"` | `"New Workspace…"` |
| `"Remove worktree \"\(worktree.name)\"?"` | `"Remove workspace \"\(worktree.name)\"?"` |
| `"This worktree has uncommitted changes. Removing it will permanently discard them."` | `"This workspace has uncommitted changes. Removing it will permanently discard them."` |
| `"Primary worktree"` | `"Primary workspace"` |
| `"External worktree"` | `"External workspace"` |

- [ ] **Step 2: Build + test**

Run: `swift build 2>&1 | tail -5`
Expected: SUCCESS.

Run: `swift test 2>&1 | tail -3`
Expected: all green.

- [ ] **Step 3: Commit**

```bash
jj commit -m "ui(sidebar): relabel WorktreePopover strings to Workspace"
```

---

## Task 2: Project row context menu + alerts relabel

**Files:**
- Modify: `Muxy/Views/Sidebar/ProjectRow.swift`
- Modify: `Muxy/Views/Sidebar/ExpandedProjectRow.swift`

- [ ] **Step 1: Apply substitutions in `ProjectRow.swift`**

| Old | New |
|-----|-----|
| `Button("Refresh Worktrees")` | `Button("Refresh Workspaces")` |
| `Button("New Worktree…")` | `Button("New Workspace…")` |
| `Button("Switch Worktree…")` | `Button("Switch Workspace…")` |

- [ ] **Step 2: Apply substitutions in `ExpandedProjectRow.swift`**

| Old | New |
|-----|-----|
| `Button("Refresh Worktrees")` | `Button("Refresh Workspaces")` |
| `Button("New Worktree…")` | `Button("New Workspace…")` |
| `worktreesExpanded ? "Collapse Worktrees" : "Expand Worktrees"` | `worktreesExpanded ? "Collapse Workspaces" : "Expand Workspaces"` |
| `"A worktree named '\(name)' is already tracked for this project."` | `"A workspace named '\(name)' is already tracked for this project."` |
| `"A worktree at this path is already tracked: \(path)"` | `"A workspace at this path is already tracked: \(path)"` |
| `", worktree: \(worktree.isPrimary ? "primary" : worktree.name)"` | `", workspace: \(worktree.isPrimary ? "primary" : worktree.name)"` |
| `"Remove worktree \"\(worktree.name)\"?"` | `"Remove workspace \"\(worktree.name)\"?"` |
| `"This worktree has uncommitted changes. Removing it will permanently discard them."` | `"This workspace has uncommitted changes. Removing it will permanently discard them."` |
| `Text("Primary worktree")` | `Text("Primary workspace")` |
| `Text("External worktree")` | `Text("External workspace")` |
| `Text("New Worktree")` | `Text("New Workspace")` |
| `.accessibilityLabel("New Worktree")` | `.accessibilityLabel("New Workspace")` |

- [ ] **Step 3: Build + test**

Run: `swift build 2>&1 | tail -5`; expected SUCCESS.
Run: `swift test 2>&1 | tail -3`; expected all green.

- [ ] **Step 4: Commit**

```bash
jj commit -m "ui(sidebar): relabel project row strings to Workspace"
```

---

## Task 3: CreateWorktreeSheet relabel

**Files:**
- Modify: `Muxy/Views/Sidebar/CreateWorktreeSheet.swift`

- [ ] **Step 1: Apply substitutions**

The sheet still creates jj workspaces / git worktrees backed by the `worktree.json` config file. Keep the file path mention but switch other UI strings.

| Old | New |
|-----|-----|
| `Text("New Worktree")` | `Text("New Workspace")` |
| `Text("Setup commands from .muxy/worktree.json")` | `Text("Setup commands from .muxy/worktree.json")` *(unchanged — file path)* |
| `Text("These commands will run in the new worktree's terminal. Only enable this if you trust this repository.")` | `Text("These commands will run in the new workspace's terminal. Only enable this if you trust this repository.")` |
| `Toggle("Run these commands after creating the worktree", isOn: $runSetup)` | `Toggle("Run these commands after creating the workspace", isOn: $runSetup)` |
| `Text("To run setup commands after creating a worktree, add .muxy/worktree.json in this repository.")` | `Text("To run setup commands after creating a workspace, add .muxy/worktree.json in this repository.")` |
| `Text("\(project.path)/.muxy/worktree.json")` | `Text("\(project.path)/.muxy/worktree.json")` *(unchanged — file path)* |
| `errorMessage = "A worktree with this name already exists on disk."` | `errorMessage = "A workspace with this name already exists on disk."` |

The two unchanged rows are listed for clarity — do not edit them.

- [ ] **Step 2: Build + test**

`swift build 2>&1 | tail -5` → SUCCESS. `swift test 2>&1 | tail -3` → all green.

- [ ] **Step 3: Commit**

```bash
jj commit -m "ui(sheet): relabel CreateWorktreeSheet strings to Workspace"
```

---

## Task 4: Refresh helper + global switcher relabel

**Files:**
- Modify: `Muxy/Views/Sidebar/WorktreeRefreshHelper.swift`
- Modify: `Muxy/Views/Components/WorktreeSwitcherOverlay.swift`

- [ ] **Step 1: `WorktreeRefreshHelper.swift`**

| Old | New |
|-----|-----|
| `alert.messageText = "Could Not Refresh Worktrees"` | `alert.messageText = "Could Not Refresh Workspaces"` |

- [ ] **Step 2: `WorktreeSwitcherOverlay.swift`**

| Old | New |
|-----|-----|
| `placeholder: "Search worktrees by name, branch, or project...",` | `placeholder: "Search workspaces by name, branch, or project...",` |
| `emptyLabel: "No worktrees",` | `emptyLabel: "No workspaces",` |
| `noMatchLabel: "No matching worktrees",` | `noMatchLabel: "No matching workspaces",` |

- [ ] **Step 3: Build + test**

`swift build 2>&1 | tail -5` → SUCCESS. `swift test 2>&1 | tail -3` → all green.

- [ ] **Step 4: Commit**

```bash
jj commit -m "ui(switcher): relabel refresh + switcher strings to Workspace"
```

---

## Task 5: Settings + commands menu + ShortcutAction display name

**Files:**
- Modify: `Muxy/Views/Settings/GeneralSettingsView.swift`
- Modify: `Muxy/Models/KeyBinding.swift` (only the `metadata` switch case for `.switchWorktree`)
- Modify: `Muxy/Commands/MuxyCommands.swift` (menu button "Switch Worktree...")

- [ ] **Step 1: `GeneralSettingsView.swift`**

| Old | New |
|-----|-----|
| `footer: "Automatically reveal worktrees when you switch to a project."` | `footer: "Automatically reveal workspaces when you switch to a project."` |
| `label: "Auto-expand worktrees on project switch",` | `label: "Auto-expand workspaces on project switch",` |

The constant `static let autoExpandWorktreesOnProjectSwitch = "muxy.general.autoExpandWorktreesOnProjectSwitch"` stays unchanged (it's a UserDefaults key, not user-visible).

- [ ] **Step 2: `KeyBinding.swift`**

In the `metadata` switch (around line 160), change ONLY the displayName for `.switchWorktree`:

```swift
        case .switchWorktree: ShortcutMetadata(displayName: "Switch Workspace", category: "Project Navigation", scope: .mainWindow)
```

The enum case `case switchWorktree` stays unchanged (it's a stable persistence identifier for keybindings).

- [ ] **Step 3: `MuxyCommands.swift`**

In `CommandGroup(after: .sidebar)` block (around line 230):

```swift
            Button("Switch Workspace...") {
                guard isMainWindowFocused else { return }
                performShortcutAction(.switchWorktree)
            }
            .shortcut(for: .switchWorktree, store: keyBindings)
```

(Only the button label changes; the `.switchWorktree` action reference stays.)

- [ ] **Step 4: Build + test**

`swift build 2>&1 | tail -5` → SUCCESS. `swift test 2>&1 | tail -3` → all green.

- [ ] **Step 5: Commit**

```bash
jj commit -m "ui(menus): relabel Switch Worktree command to Workspace"
```

---

## Task 6: Migration plan note + close-out

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Update Phase 4 section**

Locate the Phase 4 block (around line 357). Append at the bottom of the section:

```markdown
**Status (2026-04-28): Phase 4a (UI relabel) landed.**

- All user-facing "Worktree" / "worktree" strings rewritten to "Workspace" / "workspace" across sidebar (popover, project row, expanded row), creation sheet, refresh alert, global switcher overlay, settings, and File menu.
- Wholesale rename — no per-VcsKind branching. Roost is jj-first; "Workspace" is acceptable umbrella terminology for git projects.
- Internal type names (`Worktree`, `WorktreeStore`, `WorktreeKey`, `WorktreeDTO`, `WorktreeConfig`) and persistence (UserDefaults keys, `.muxy/worktree.json` config path) **kept** for backwards compatibility. Renaming model identifiers and migrating persistence is out of scope.
- ShortcutAction enum case `.switchWorktree` kept (stable keybinding identifier); only its `displayName` changed.
- Phase 4b (op_heads watcher + dirty/conflict badges), 4c (session list under workspace), 4d (`requiresDedicatedWorkspace` enforcement) → upcoming.
```

- [ ] **Step 2: Run final checks**

`scripts/checks.sh 2>&1 | tail -10` (best effort — this repo's checks script may have known issues with generated files; the lint check should be clean for hand-written files in `Muxy/` and `MuxyShared/`). At minimum: `swift test 2>&1 | tail -3` → all green.

- [ ] **Step 3: Commit**

```bash
jj commit -m "docs(plan): mark Phase 4a (UI relabel) landed"
```

---

## Self-Review Checklist

- [ ] All 39 occurrences of user-visible "Worktree" / "worktree" rewritten to "Workspace" / "workspace".
- [ ] Zero internal Swift identifier renamed.
- [ ] Zero file path / UserDefaults key changed.
- [ ] All builds and tests pass after each commit.
- [ ] No new tests required — string substitutions don't change behavior. (If existing tests start failing it means a string was inadvertently changed inside non-UI logic — investigate.)
