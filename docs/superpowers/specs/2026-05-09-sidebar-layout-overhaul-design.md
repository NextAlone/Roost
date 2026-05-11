# Sidebar Layout Overhaul Design

## Goal

Reduce friction when switching between many projects in the Roost sidebar. Three user-visible changes:

1. Move the per-project "New Workspace…" action out of each expanded project row into a single always-visible entry pinned to the top of the sidebar, next to Scratch.
2. Offer an opt-in project sort mode that promotes projects with recent agent activity to the top, while preserving the existing manual drag order when the mode is off.
3. Surface a top-pinned "agents awaiting input" indicator that lets the user jump straight to the pane that needs attention.

Scratch becomes permanently pinned at the top of the sidebar, mirroring how "Add Project" is permanently pinned at the bottom.

## Non-Goals

- Time-bucketed section headers (1h / 2h / 4h groups). A single flat list with a 4h boundary is enough.
- Sorting individual worktrees inside a project. Worktree order inside a project stays at creation order.
- Pane-level activity indicators in the main sidebar list. The "needs attention" signal lives only in the top banner.
- A configurable "active" threshold. Four hours is hardcoded.
- Detecting activity from raw terminal output. Ghostty exposes no `didReceiveOutput` callback (`GhosttyTerminalNSView.swift:698`, `RemoteServerDelegate.swift:253` only offer on-demand `ghostty_surface_read_cells`), and polling is out of scope.
- Sound / Dock badge notifications for awaiting agents.
- Editing the new `+ Workspace` button's target via a project picker. The button targets `AppState.activeProjectID`; if nothing is active it is disabled.

## Background

`Muxy/Views/Sidebar.swift` currently renders three regions in a single `VStack`:

- `projectList` (a `ScrollView` + `LazyVStack`) whose first child is `ScratchRow` (or `ScratchCollapsedRow`) followed by one row per project.
- `addProjectBar` (fixed, non-scrolling) that hosts the `AddProjectButton`.
- `SidebarFooter` (fixed, non-scrolling).

Each `ExpandedProjectRow` embeds a prominent inline `ExpandedNewWorktreeButton` at the end of its worktree list (`Muxy/Views/Sidebar/ExpandedProjectRow.swift:310-318`) and a context-menu entry `Button("New Workspace…")` at `ExpandedProjectRow.swift:126`. When the user has many projects expanded the inline button multiplies visual noise; the context-menu entry is hidden until right-click and costs nothing.

Projects today sort purely by `Project.sortOrder` (manual drag; `Muxy/Models/Project.swift`). Roost has no persisted "last active" signal on a worktree.

The agent activity model already provides a coarse, push-based signal. `AppState.updateAgentActivity` (`Muxy/Models/AppState.swift:285-320`) is the single write path for agent activity, fed by `NotificationSocketServer` (`roost.sock` endpoint, `NotificationSocketServer.swift:170`). A dirty-counter `agentActivityRevision` is bumped on every update (`AppState.swift:127`), and `ScratchRow.swift:19` already demonstrates the `_ = appState.agentActivityRevision` read pattern to trigger SwiftUI view invalidation. `AgentActivityState.awaiting` (`MuxyShared/Agent/AgentActivityState.swift:5`) marks panes that need user input.

`AppState.activeProjectID: UUID?` (`Muxy/Models/AppState.swift:109`) already tracks the focused project. Worktree metadata persistence lives in `WorktreeStore` with per-project JSON files (`Muxy/Services/WorktreeStore.swift`), where fields like `sortOrder` and `isPrimary` are persisted alongside identity.

## Decision

Keep the existing `AppState.dispatch → WorkspaceReducer.reduce` path for workspace topology. Treat `lastActiveAt` as worktree metadata (same category as `sortOrder` and `isPrimary`) and persist it directly through `WorktreeStore`, bypassing the reducer. Drive activity updates from `AppState.updateAgentActivity` only; do not add a terminal-output hook.

Restructure the sidebar into four regions:

```text
┌──────────────────────────────┐
│ Scratch row                  │ fixed top
│ Pending banner (conditional) │ fixed top, hidden when count == 0
│ + Workspace                  │ fixed top, disabled when no active project
├──────────────────────────────┤
│ ScrollView (project rows)    │ sorted by projectSortMode
├──────────────────────────────┤
│ + Add Project                │ fixed bottom (existing)
│ SidebarFooter                │ fixed bottom (existing)
└──────────────────────────────┘
```

Add a single user-controlled toggle `projectSortMode = .manual | .active`, surfaced only through a right-click menu in the project list area. Default is `.manual` (backwards compatible).

## Architecture

### Data model changes

`Muxy/Models/Worktree.swift`

- Add `var lastActiveAt: Date?` (optional, `Codable`).
- Extend `init(from decoder:)` with `lastActiveAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveAt)` for forward compatibility with existing on-disk JSON.

`Muxy/Models/Project.swift`

- Add a computed `var lastActiveAt: Date?` that returns `worktrees.compactMap(\.lastActiveAt).max()`. The worktree list is supplied by `WorktreeStore`, so the accessor lives on a light view model or a helper rather than on `Project` directly to avoid coupling the persisted model to the store. Preferred location: a free function in `Muxy/Services/ProjectSortingService.swift` that takes `(Project, [Worktree]) -> Date?`.

New storage keys:

- `@AppStorage("muxy.projectSortMode")`: raw value of an enum `ProjectSortMode: String, CaseIterable { case manual, active }`. Default `.manual`.

### Activity tracking

Single source of truth is `AppState.updateAgentActivity` (`AppState.swift:285-320`). Inside that method, after the local `activityState` and `agentActivityRevision` updates, resolve the `(projectID, worktreeID)` for the pane from the existing `paneState → workspace → worktree` mapping and invoke:

```swift
worktreeStore.markActive(projectID: projectID, worktreeID: worktreeID, at: Date())
```

`WorktreeStore.markActive(projectID:worktreeID:at:)` mutates the in-memory `Worktree.lastActiveAt`, then schedules a 1-second debounce before calling the existing `save(projectID:)` path (`WorktreeStore.swift:417-422`). Consecutive `markActive` calls for the same project collapse into one write.

No per-worktree throttle layer is introduced: `updateAgentActivity` is already driven by discrete agent state transitions (not a continuous stream), so the upstream event rate is low.

### Sort pipeline

`ProjectSortingService.sortedProjects(_ projects: [Project], worktreesByProject: [UUID: [Worktree]], mode: ProjectSortMode, now: Date) -> [Project]`

```text
if mode == .manual:
    return projects.sorted(by: { $0.sortOrder < $1.sortOrder })

let threshold = now - 4h
let (recent, rest) = projects.partition { lastActiveAt($0) ?? .distantPast >= threshold }
recent.sort(by: { lastActiveAt($0)! > lastActiveAt($1)! })  // desc
rest.sort(by: { $0.sortOrder < $1.sortOrder })              // asc, existing manual order
return recent + rest
```

`Sidebar.projectList` invokes this service before passing projects into its `ForEach`. The service is pure: tests cover it without touching views.

### Project drag behavior

When `projectSortMode == .active`, `Sidebar.projectDragGesture(for:)` short-circuits and does not install a drag gesture (matches Finder "Sort by Date" behavior: Finder disables manual reorder while sorted). Switching back to `.manual` restores drag. No auto-switch on drag attempt.

### Pending banner

Add a computed property on `AppState`:

```swift
var awaitingPanes: [AwaitingPaneSummary] {
    _ = agentActivityRevision
    return paneStates
        .filter { $0.value.activityState == .awaiting }
        .map { AwaitingPaneSummary(paneID: $0.key, projectName:, workspaceName:, paneTitle:) }
        .sorted(by: …)
}
```

`AwaitingPaneSummary` is a small value type local to `Muxy/Views/Sidebar/PendingAgentsBanner.swift`. The view observes `appState.awaitingPanes`; SwiftUI recomputes it whenever `agentActivityRevision` changes, so no additional subscription layer is needed.

Banner view behavior:

- `count == 0` → `EmptyView()` so the row takes zero height.
- `count > 0` → single-row clickable cell showing `⚠ \(count) agent\(count == 1 ? "" : "s") awaiting`. Opens a SwiftUI `Popover` anchored to the row.
- Popover lists each `AwaitingPaneSummary` row. Row tap dispatches the existing "navigate to pane" reducer action (exact action name identified during implementation from `WorkspaceReducer`; if one does not exist yet, a new `Action.focusPane(paneID:)` is added, keeping the mutation on the reducer path). Popover closes on selection.
- In the collapsed sidebar (`ScratchCollapsedRow` style), the banner renders as a compact circular badge with a count number, same tap target.

### + Workspace button

New view `Muxy/Views/Sidebar/NewWorkspaceButton.swift`.

- Reads `appState.activeProjectID`.
- If `nil` or equals `Project.scratchID`: button is visually present but disabled with tooltip "Select a project first".
- If set: tap opens the existing `CreateWorktreeSheet` bound to that project, using the same initialization path currently invoked from `ExpandedProjectRow`. Implementation inspects `CreateWorktreeSheet.swift` to reuse or mildly refactor that path.
- Remove the inline `ExpandedNewWorktreeButton` call at `ExpandedProjectRow.swift:310-312`, which is the visually noisy duplicate. Keep the right-click context-menu entry `Button("New Workspace…")` at `ExpandedProjectRow.swift:126` and keep the `.popover(isPresented: $showCreateWorktreeSheet)` at `ExpandedProjectRow.swift:313-318`, since `showCreateWorktreeSheet` is also toggled by the context-menu entry and by the agent-requested-workspace notification handler at `ExpandedProjectRow.swift:131-138`.

### Right-click toggle

Attach a `.contextMenu` to the project list container in `Sidebar.swift`. Entries:

- `Sort: Manual` (checkmark when `.manual`)
- `Sort: Recently Active` (checkmark when `.active`)

Selecting an entry writes the new value to the `@AppStorage`-backed binding. No settings-page surface; if a user needs it later it is a trivial addition.

### Persistence

`Worktree.lastActiveAt` rides in the existing per-project `WorktreeStore` JSON. No new file, no migration. Old on-disk data decodes with `lastActiveAt == nil`, which naturally lands the project in the `rest` partition under `.active` mode.

`projectSortMode` is `@AppStorage` only; no migration.

### Testing

`Tests/MuxyTests/` gets three new test files:

- `ProjectSortingServiceTests` covers `.manual` preservation, `.active` partitioning at the 4h boundary, `nil` lastActiveAt handling, and stability of the `rest` partition.
- `WorktreeStoreMarkActiveTests` covers `markActive` mutating in-memory state immediately, debouncing writes, and round-tripping `lastActiveAt` through JSON encode/decode including missing-field legacy payloads.
- `AwaitingPanesTests` covers `AppState.awaitingPanes` recomputation triggered by `agentActivityRevision` bumps, including a pane transitioning out of `.awaiting`.

No new UI snapshot tests beyond existing conventions.

## Risks and Open Questions

- Debounced writes on app termination: if the user quits during the 1-second debounce, the most recent activity timestamp is lost. Acceptable. If needed later, flush on `applicationWillTerminate`.
- `activeProjectID == Project.scratchID`: Scratch is treated as "no project" for the purposes of the `+ Workspace` button (disabled state). Verified against `Project.swift:5` where `scratchID` is fixed.
- Ghostty exposes only pull-based `read_cells`; tying activity to the agent-state signal means an idle pane that is still producing output will not bump its workspace. Acceptable for a first pass — the "agent needs input" banner covers the urgent case; sort ordering only needs a coarse recency signal.

## Rollout

Single feature. Ship together.
