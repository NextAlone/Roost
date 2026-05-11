# Sidebar Layout Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin Scratch / pending-agents banner / "+ Workspace" to the sidebar top, make project sort opt-in by recent activity, and remove the inline per-project new-workspace button.

**Architecture:** Persist `lastActiveAt` on each `Worktree` and bump it from `AppState.updateAgentActivity` via a new `WorktreeStore.markActive` with debounced writes. A pure `ProjectSortingService` decides project order based on an `@AppStorage` mode (`.manual` default, `.active` opt-in). Sidebar top region becomes a fixed `VStack` hosting `ScratchRow`, a conditional `PendingAgentsBanner`, and a new `NewWorkspaceButton` bound to `AppState.activeProjectID`.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, SwiftPM tests (`swift test --filter RoostTests.<Suite>`), jj for VCS.

**Spec:** `docs/superpowers/specs/2026-05-09-sidebar-layout-overhaul-design.md`

**VCS policy:** Repository is `jj`-managed. Every commit step uses `jj commit -m "…"` (or `jj describe -m`/`jj new`). Never invoke `git` directly.

---

## File Structure

Created files:

- `Muxy/Models/ProjectSortMode.swift` — new enum + raw-value bridge for `@AppStorage`.
- `Muxy/Services/ProjectSortingService.swift` — pure sorting function.
- `Muxy/Views/Sidebar/NewWorkspaceButton.swift` — top-pinned `+ Workspace` view.
- `Muxy/Views/Sidebar/PendingAgentsBanner.swift` — top-pinned conditional banner + popover.
- `Tests/MuxyTests/Sidebar/ProjectSortingServiceTests.swift`
- `Tests/MuxyTests/Sidebar/WorktreeStoreMarkActiveTests.swift`
- `Tests/MuxyTests/Sidebar/AwaitingPanesTests.swift`
- `Tests/MuxyTests/Sidebar/WorktreeCodableTests.swift`

Modified files:

- `Muxy/Models/Worktree.swift` — add `lastActiveAt: Date?` and decode path.
- `Muxy/Services/WorktreeStore.swift` — add `markActive(projectID:worktreeID:at:)`, debounce timer, expose `save` via the new path.
- `Muxy/Models/AppState.swift` — call `markActive` from `updateAgentActivity`, expose `awaitingPanes` computed, allow read of `WorktreeStore` reference.
- `Muxy/Views/Sidebar.swift` — restructure body, add fixed top `VStack`, thread the new sort mode through `projectList`, condition drag gesture on mode, attach context-menu with sort toggle.
- `Muxy/Views/Sidebar/ExpandedProjectRow.swift` — remove inline `ExpandedNewWorktreeButton` call at L310-312 and the trailing `ExpandedNewWorktreeButton` struct definition at L875 if unused elsewhere.

---

### Task 1: Prep branch and verify baseline

**Files:**
- No edits; environment prep.

- [ ] **Step 1.1: Confirm clean working copy**

Run: `jj st`
Expected: Empty or only user-chosen unrelated changes. If there are unrelated changes, stop and resolve with the user.

- [ ] **Step 1.2: Create a focused change**

Run: `jj new -m "feat: sidebar layout overhaul (WIP)"`
Expected: New empty revision on top of current `@`.

- [ ] **Step 1.3: Baseline build and tests**

Run: `swift build`
Expected: Success.

Run: `swift test`
Expected: All existing tests pass. Note the baseline; any pre-existing failure must be reported before continuing.

---

### Task 2: Add `lastActiveAt` to `Worktree`

**Files:**
- Modify: `Muxy/Models/Worktree.swift`
- Test: `Tests/MuxyTests/Sidebar/WorktreeCodableTests.swift`

- [ ] **Step 2.1: Write the failing test**

Create `Tests/MuxyTests/Sidebar/WorktreeCodableTests.swift`:

```swift
import XCTest
@testable import Roost
@testable import MuxyShared

final class WorktreeCodableTests: XCTestCase {
    func testDecodesLegacyPayloadWithoutLastActiveAt() throws {
        let json = #"""
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "default",
            "path": "/tmp/p",
            "ownsBranch": false,
            "source": "muxy",
            "isPrimary": true,
            "createdAt": 0,
            "vcsKind": "git"
        }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Worktree.self, from: json)
        XCTAssertNil(decoded.lastActiveAt)
    }

    func testRoundTripsLastActiveAt() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var worktree = Worktree(name: "x", path: "/tmp/x", isPrimary: false)
        worktree.lastActiveAt = date
        let data = try JSONEncoder().encode(worktree)
        let decoded = try JSONDecoder().decode(Worktree.self, from: data)
        XCTAssertEqual(decoded.lastActiveAt, date)
    }
}
```

- [ ] **Step 2.2: Run the test, confirm it fails**

Run: `swift test --filter RoostTests.WorktreeCodableTests`
Expected: Compilation failure — `lastActiveAt` is not a member of `Worktree` yet.

- [ ] **Step 2.3: Add the field and Codable plumbing**

Edit `Muxy/Models/Worktree.swift`:

Under the stored properties (after `var jjWorkspaceName: String?`), add:

```swift
    var lastActiveAt: Date?
```

In `init(...)` add a parameter `lastActiveAt: Date? = nil` (place it right after `jjWorkspaceName`) and assign `self.lastActiveAt = lastActiveAt` in the body.

Add to `CodingKeys`:

```swift
        case lastActiveAt
```

In `init(from decoder:)` add after the `jjWorkspaceName` decode:

```swift
        lastActiveAt = try container.decodeIfPresent(Date.self, forKey: .lastActiveAt)
```

No explicit `encode(to:)` exists; the synthesized encoder picks up the new optional key automatically.

- [ ] **Step 2.4: Run tests, confirm pass**

Run: `swift test --filter RoostTests.WorktreeCodableTests`
Expected: Both tests pass.

- [ ] **Step 2.5: Full test run**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 2.6: Commit**

Run:
```
jj commit -m "feat(worktree): add lastActiveAt field with backwards-compatible decoding"
```

---

### Task 3: `WorktreeStore.markActive` with debounced save

**Files:**
- Modify: `Muxy/Services/WorktreeStore.swift`
- Test: `Tests/MuxyTests/Sidebar/WorktreeStoreMarkActiveTests.swift`

- [ ] **Step 3.1: Study the existing persistence test pattern**

Run: `ls Tests/MuxyTests | grep -i worktree`
Expected: Review existing worktree-related test files to see how `InMemoryWorktreePersistence` (or similar fake) is constructed. Reuse the same helper in the new test.

- [ ] **Step 3.2: Write the failing test**

Create `Tests/MuxyTests/Sidebar/WorktreeStoreMarkActiveTests.swift`:

```swift
import XCTest
@testable import Roost
@testable import MuxyShared

@MainActor
final class WorktreeStoreMarkActiveTests: XCTestCase {
    func testMarkActiveUpdatesInMemory() async throws {
        let project = Project(name: "p", path: "/tmp/p")
        let persistence = InMemoryWorktreePersistence()
        let primary = Worktree(name: "default", path: "/tmp/p", isPrimary: true)
        try persistence.saveWorktrees([primary], projectID: project.id)
        let store = WorktreeStore(persistence: persistence, projects: [project])

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.markActive(projectID: project.id, worktreeID: primary.id, at: now)

        XCTAssertEqual(store.worktree(projectID: project.id, worktreeID: primary.id)?.lastActiveAt, now)
    }

    func testMarkActivePersistsAfterDebounce() async throws {
        let project = Project(name: "p", path: "/tmp/p")
        let persistence = InMemoryWorktreePersistence()
        let primary = Worktree(name: "default", path: "/tmp/p", isPrimary: true)
        try persistence.saveWorktrees([primary], projectID: project.id)
        let store = WorktreeStore(
            persistence: persistence,
            projects: [project],
            saveDebounce: .milliseconds(10)
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.markActive(projectID: project.id, worktreeID: primary.id, at: now)
        try await Task.sleep(for: .milliseconds(30))

        let reloaded = try persistence.loadWorktrees(projectID: project.id)
        XCTAssertEqual(reloaded.first?.lastActiveAt, now)
    }

    func testMarkActiveCollapsesBurstIntoSingleWrite() async throws {
        let project = Project(name: "p", path: "/tmp/p")
        let persistence = CountingPersistence(inner: InMemoryWorktreePersistence())
        let primary = Worktree(name: "default", path: "/tmp/p", isPrimary: true)
        try persistence.saveWorktrees([primary], projectID: project.id)
        persistence.saveCount = 0
        let store = WorktreeStore(
            persistence: persistence,
            projects: [project],
            saveDebounce: .milliseconds(10)
        )

        for i in 0 ..< 5 {
            store.markActive(
                projectID: project.id,
                worktreeID: primary.id,
                at: Date(timeIntervalSince1970: 1_700_000_000 + Double(i))
            )
        }
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(persistence.saveCount, 1)
    }
}
```

If `InMemoryWorktreePersistence` does not already exist, add a minimal test double at the top of this file:

```swift
final class InMemoryWorktreePersistence: WorktreePersisting {
    var storage: [UUID: [Worktree]] = [:]
    func loadWorktrees(projectID: UUID) throws -> [Worktree] { storage[projectID] ?? [] }
    func saveWorktrees(_ list: [Worktree], projectID: UUID) throws { storage[projectID] = list }
}

final class CountingPersistence: WorktreePersisting {
    let inner: any WorktreePersisting
    var saveCount = 0
    init(inner: any WorktreePersisting) { self.inner = inner }
    func loadWorktrees(projectID: UUID) throws -> [Worktree] {
        try inner.loadWorktrees(projectID: projectID)
    }
    func saveWorktrees(_ list: [Worktree], projectID: UUID) throws {
        saveCount += 1
        try inner.saveWorktrees(list, projectID: projectID)
    }
}
```

- [ ] **Step 3.3: Run the test, confirm it fails**

Run: `swift test --filter RoostTests.WorktreeStoreMarkActiveTests`
Expected: Compilation failure — `markActive` does not exist, `saveDebounce` parameter does not exist.

- [ ] **Step 3.4: Implement `markActive` and the debounce parameter**

Edit `Muxy/Services/WorktreeStore.swift`:

Add to the class stored properties (below `listJjWorkspaces`):

```swift
    private let saveDebounce: Duration
    private var pendingSaveTasks: [UUID: Task<Void, Never>] = [:]
```

Extend the initializer signature to accept `saveDebounce: Duration = .seconds(1)` and capture it:

```swift
    init(
        persistence: any WorktreePersisting,
        listGitWorktrees: @escaping @Sendable (String) async throws -> [GitWorktreeRecord] = {
            try await GitWorktreeService.shared.listWorktrees(repoPath: $0)
        },
        listJjWorkspaces: @escaping @Sendable (String) async throws -> [JjWorkspaceEntry] = { repoPath in
            let service = JjWorkspaceService(queue: JjProcessQueue.shared)
            return try await service.list(repoPath: repoPath)
        },
        projects: [Project] = [],
        saveDebounce: Duration = .seconds(1)
    ) {
        self.persistence = persistence
        self.listGitWorktrees = listGitWorktrees
        self.listJjWorkspaces = listJjWorkspaces
        self.saveDebounce = saveDebounce
        guard !projects.isEmpty else { return }
        loadAll(projects: projects)
    }
```

Add the public method above `private func save`:

```swift
    func markActive(projectID: UUID, worktreeID: UUID, at date: Date) {
        guard var list = worktrees[projectID] else { return }
        guard let index = list.firstIndex(where: { $0.id == worktreeID }) else { return }
        list[index].lastActiveAt = date
        setWorktrees(list, for: projectID)
        scheduleDebouncedSave(projectID: projectID)
    }

    private func scheduleDebouncedSave(projectID: UUID) {
        pendingSaveTasks[projectID]?.cancel()
        let debounce = saveDebounce
        pendingSaveTasks[projectID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            self.save(projectID: projectID)
            self.pendingSaveTasks[projectID] = nil
        }
    }
```

- [ ] **Step 3.5: Run the tests, confirm pass**

Run: `swift test --filter RoostTests.WorktreeStoreMarkActiveTests`
Expected: All three tests pass.

- [ ] **Step 3.6: Full test run**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 3.7: Commit**

Run:
```
jj commit -m "feat(worktree-store): add markActive with debounced persistence"
```

---

### Task 4: Wire `AppState.updateAgentActivity` to `markActive`

**Files:**
- Modify: `Muxy/Models/AppState.swift:285-320`
- Test: `Tests/MuxyTests/Sidebar/AwaitingPanesTests.swift` (partial — covers this too)

- [ ] **Step 4.1: Inspect current `AppState` constructor**

Open `Muxy/Models/AppState.swift` and locate the initializer. Identify where `WorktreeStore` is injected (the store is accessed from `ExpandedProjectRow` through `@Environment(WorktreeStore.self)`; `AppState` itself may not hold a reference yet).

If `AppState` does **not** already own or reference `WorktreeStore`, add a weak reference:

```swift
    weak var worktreeStore: WorktreeStore?
```

Wire it from the app composition root (search for where `AppState()` is instantiated — typically in `MuxyApp.swift`) by assigning `appState.worktreeStore = worktreeStore` once both objects are constructed.

- [ ] **Step 4.2: Hook into `updateAgentActivity`**

In `Muxy/Models/AppState.swift`, inside `updateAgentActivity` at line 306 (right after `advanceAgentActivityRevision()`), add:

```swift
                    worktreeStore?.markActive(
                        projectID: key.projectID,
                        worktreeID: key.worktreeID,
                        at: Date()
                    )
```

- [ ] **Step 4.3: Add the integration test**

Create `Tests/MuxyTests/Sidebar/AwaitingPanesTests.swift` (this file grows further in Task 6; scaffold with one test now):

```swift
import XCTest
@testable import Roost
@testable import MuxyShared

@MainActor
final class AwaitingPanesTests: XCTestCase {
    func testUpdateAgentActivityBumpsWorktreeLastActiveAt() throws {
        let project = Project(name: "p", path: "/tmp/p")
        let persistence = InMemoryWorktreePersistence()
        let primary = Worktree(name: "default", path: "/tmp/p", isPrimary: true)
        try persistence.saveWorktrees([primary], projectID: project.id)
        let store = WorktreeStore(persistence: persistence, projects: [project])
        let appState = AppState()
        appState.worktreeStore = store

        let paneID = UUID()
        let key = WorktreeKey(projectID: project.id, worktreeID: primary.id)
        appState.seedWorkspaceForTesting(key: key, paneID: paneID)

        let before = Date()
        _ = appState.updateAgentActivity(paneID: paneID, state: .awaiting)
        let after = Date()

        let stamp = store.worktree(projectID: project.id, worktreeID: primary.id)?.lastActiveAt
        XCTAssertNotNil(stamp)
        XCTAssertGreaterThanOrEqual(stamp!, before)
        XCTAssertLessThanOrEqual(stamp!, after)
    }
}
```

`seedWorkspaceForTesting` is a small test affordance. If an equivalent helper already exists in `Tests/MuxyTests/` (search for any method that inserts a pane into `workspaceRoots`), reuse it. Otherwise add the following at the bottom of `AppState.swift`, guarded with `#if DEBUG` since it mutates internals for tests:

```swift
#if DEBUG
extension AppState {
    func seedWorkspaceForTesting(key: WorktreeKey, paneID: UUID) {
        // Wire one root → area → tab → pane entry using existing public constructors.
        // Implementation mirrors the smallest working graph used elsewhere in test code.
    }
}
#endif
```

Replace the placeholder body with the smallest code that produces one `WorkspaceRoot` under `key` whose single area has one tab whose `content.pane.id == paneID`. Refer to how test code (search `workspaceRoots` under `Tests/`) constructs this graph today and copy the same pattern.

- [ ] **Step 4.4: Build and run the test**

Run: `swift test --filter RoostTests.AwaitingPanesTests/testUpdateAgentActivityBumpsWorktreeLastActiveAt`
Expected: Pass.

- [ ] **Step 4.5: Full test run**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 4.6: Commit**

Run:
```
jj commit -m "feat(app-state): stamp worktree lastActiveAt from agent activity updates"
```

---

### Task 5: `ProjectSortMode` enum + `@AppStorage` binding

**Files:**
- Create: `Muxy/Models/ProjectSortMode.swift`
- Test: none; this is a trivial raw-value enum covered by Task 6.

- [ ] **Step 5.1: Create the enum file**

Create `Muxy/Models/ProjectSortMode.swift`:

```swift
import Foundation

enum ProjectSortMode: String, CaseIterable, Identifiable {
    case manual
    case active

    static let storageKey = "muxy.projectSortMode"
    static let defaultValue: ProjectSortMode = .manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: "Manual"
        case .active: "Recently Active"
        }
    }
}
```

- [ ] **Step 5.2: Build**

Run: `swift build`
Expected: Success.

- [ ] **Step 5.3: Commit**

Run:
```
jj commit -m "feat(sidebar): introduce ProjectSortMode enum"
```

---

### Task 6: `ProjectSortingService` pure function

**Files:**
- Create: `Muxy/Services/ProjectSortingService.swift`
- Test: `Tests/MuxyTests/Sidebar/ProjectSortingServiceTests.swift`

- [ ] **Step 6.1: Write failing tests**

Create `Tests/MuxyTests/Sidebar/ProjectSortingServiceTests.swift`:

```swift
import XCTest
@testable import Roost
@testable import MuxyShared

final class ProjectSortingServiceTests: XCTestCase {
    private func project(_ name: String, sortOrder: Int) -> Project {
        var p = Project(name: name, path: "/tmp/\(name)")
        p.sortOrder = sortOrder
        return p
    }

    private func worktree(lastActiveAt: Date?) -> Worktree {
        var w = Worktree(name: "default", path: "/tmp/x", isPrimary: true)
        w.lastActiveAt = lastActiveAt
        return w
    }

    func testManualModePreservesSortOrder() {
        let a = project("a", sortOrder: 2)
        let b = project("b", sortOrder: 0)
        let c = project("c", sortOrder: 1)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sorted = ProjectSortingService.sort(
            projects: [a, b, c],
            worktreesByProject: [:],
            mode: .manual,
            now: now
        )
        XCTAssertEqual(sorted.map(\.name), ["b", "c", "a"])
    }

    func testActiveModePartitionsByFourHourWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = project("a", sortOrder: 2)
        let b = project("b", sortOrder: 0)
        let c = project("c", sortOrder: 1)
        let worktreesByProject: [UUID: [Worktree]] = [
            a.id: [worktree(lastActiveAt: now.addingTimeInterval(-60 * 30))],          // 30 min ago → recent
            b.id: [worktree(lastActiveAt: now.addingTimeInterval(-60 * 60 * 5))],      // 5 h ago → rest
            c.id: [worktree(lastActiveAt: now.addingTimeInterval(-60 * 60 * 2))],      // 2 h ago → recent
        ]
        let sorted = ProjectSortingService.sort(
            projects: [a, b, c],
            worktreesByProject: worktreesByProject,
            mode: .active,
            now: now
        )
        XCTAssertEqual(sorted.map(\.name), ["a", "c", "b"])
    }

    func testActiveModePlacesNilActivityIntoRestByManualOrder() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = project("a", sortOrder: 0)
        let b = project("b", sortOrder: 1)
        let worktreesByProject: [UUID: [Worktree]] = [
            a.id: [worktree(lastActiveAt: nil)],
            b.id: [worktree(lastActiveAt: nil)],
        ]
        let sorted = ProjectSortingService.sort(
            projects: [a, b],
            worktreesByProject: worktreesByProject,
            mode: .active,
            now: now
        )
        XCTAssertEqual(sorted.map(\.name), ["a", "b"])
    }

    func testActiveModeBoundaryExactlyAtThreshold() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let onEdge = project("edge", sortOrder: 5)
        let just = project("just", sortOrder: 0)
        let worktreesByProject: [UUID: [Worktree]] = [
            onEdge.id: [worktree(lastActiveAt: now.addingTimeInterval(-60 * 60 * 4))],         // exactly 4h
            just.id:   [worktree(lastActiveAt: now.addingTimeInterval(-60 * 60 * 4 - 1))],     // 4h + 1s
        ]
        let sorted = ProjectSortingService.sort(
            projects: [onEdge, just],
            worktreesByProject: worktreesByProject,
            mode: .active,
            now: now
        )
        XCTAssertEqual(sorted.map(\.name), ["edge", "just"])
    }
}
```

- [ ] **Step 6.2: Run the tests, confirm failure**

Run: `swift test --filter RoostTests.ProjectSortingServiceTests`
Expected: Compilation failure — `ProjectSortingService` does not exist.

- [ ] **Step 6.3: Implement the service**

Create `Muxy/Services/ProjectSortingService.swift`:

```swift
import Foundation

enum ProjectSortingService {
    static let activeThreshold: TimeInterval = 60 * 60 * 4

    static func sort(
        projects: [Project],
        worktreesByProject: [UUID: [Worktree]],
        mode: ProjectSortMode,
        now: Date
    ) -> [Project] {
        guard mode == .active else {
            return projects.sorted { $0.sortOrder < $1.sortOrder }
        }
        let boundary = now.addingTimeInterval(-activeThreshold)
        let stamped: [(Project, Date?)] = projects.map {
            ($0, lastActiveAt(for: $0, worktreesByProject: worktreesByProject))
        }
        let recent = stamped
            .filter { ($0.1 ?? .distantPast) >= boundary }
            .sorted { ($0.1 ?? .distantPast) > ($1.1 ?? .distantPast) }
            .map(\.0)
        let rest = stamped
            .filter { ($0.1 ?? .distantPast) < boundary }
            .map(\.0)
            .sorted { $0.sortOrder < $1.sortOrder }
        return recent + rest
    }

    private static func lastActiveAt(
        for project: Project,
        worktreesByProject: [UUID: [Worktree]]
    ) -> Date? {
        worktreesByProject[project.id]?.compactMap(\.lastActiveAt).max()
    }
}
```

- [ ] **Step 6.4: Run the tests, confirm pass**

Run: `swift test --filter RoostTests.ProjectSortingServiceTests`
Expected: All four tests pass.

- [ ] **Step 6.5: Full test run**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 6.6: Commit**

Run:
```
jj commit -m "feat(sidebar): add ProjectSortingService pure sort function"
```

---

### Task 7: Thread sort mode + disable drag when `.active`

**Files:**
- Modify: `Muxy/Views/Sidebar.swift`

- [ ] **Step 7.1: Add `@AppStorage` binding and read sorted list**

Edit `Muxy/Views/Sidebar.swift`.

After the existing `@AppStorage(SidebarExpandedStyle.storageKey) private var expandedStyleRaw = …` line, add:

```swift
    @AppStorage(ProjectSortMode.storageKey) private var projectSortModeRaw = ProjectSortMode.defaultValue.rawValue

    private var projectSortMode: ProjectSortMode {
        ProjectSortMode(rawValue: projectSortModeRaw) ?? ProjectSortMode.defaultValue
    }

    private var sortedProjects: [Project] {
        ProjectSortingService.sort(
            projects: projectStore.projects,
            worktreesByProject: worktreeStore.worktrees,
            mode: projectSortMode,
            now: Date()
        )
    }
```

Replace the `ForEach(Array(projectStore.projects.enumerated()), id: \.element.id)` call inside `projectList` with:

```swift
                ForEach(Array(sortedProjects.enumerated()), id: \.element.id) { index, project in
```

Leave the body of the closure unchanged.

- [ ] **Step 7.2: Short-circuit drag when sort mode is `.active`**

Inside `projectDragGesture(for:)`, add an early return at the top:

Find the function signature:
```swift
    private func projectDragGesture(for project: Project) -> some Gesture {
```

Rewrite the body so the existing gesture pipeline is wrapped in a conditional:

```swift
    private func projectDragGesture(for project: Project) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("sidebar"))
            .onChanged { [projectSortMode] value in
                guard projectSortMode == .manual else { return }
                if dragState.draggedID == nil {
                    dragState.draggedID = project.id
                    dragState.lastReorderTargetID = nil
                }
                reorderIfNeeded(at: value.location)
            }
            .onEnded { [projectSortMode] _ in
                guard projectSortMode == .manual else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    // existing body kept unchanged
                }
            }
    }
```

Preserve whatever cleanup the original `.onEnded` already performed — the new code only adds the guard; do not rewrite the cleanup logic.

- [ ] **Step 7.3: Manual sanity**

Run: `swift build`
Expected: Success.

Run: `swift run Roost` (interactive)
Expected: Sidebar still functions; drag still works in default manual mode. Close the app when confirmed.

- [ ] **Step 7.4: Commit**

Run:
```
jj commit -m "feat(sidebar): sort project list by projectSortMode and gate drag on manual mode"
```

---

### Task 8: `AppState.awaitingPanes` computed

**Files:**
- Modify: `Muxy/Models/AppState.swift`
- Test: `Tests/MuxyTests/Sidebar/AwaitingPanesTests.swift` (extend)

- [ ] **Step 8.1: Add the summary type and computed property**

At the bottom of `Muxy/Models/AppState.swift` (above any `#if DEBUG` section), add:

```swift
struct AwaitingPaneSummary: Identifiable, Hashable {
    let id: UUID
    let paneID: UUID
    let projectID: UUID
    let worktreeID: UUID
    let paneTitle: String
    let projectName: String
    let workspaceName: String
}
```

Inside the `AppState` class body, near other computed properties, add:

```swift
    var awaitingPanes: [AwaitingPaneSummary] {
        _ = agentActivityRevision
        var results: [AwaitingPaneSummary] = []
        for (key, root) in workspaceRoots {
            for area in root.allAreas() {
                for tab in area.tabs {
                    guard let pane = tab.content.pane,
                          pane.activityState == .awaiting
                    else { continue }
                    results.append(AwaitingPaneSummary(
                        id: pane.id,
                        paneID: pane.id,
                        projectID: key.projectID,
                        worktreeID: key.worktreeID,
                        paneTitle: tab.title,
                        projectName: projectName(for: key.projectID) ?? "",
                        workspaceName: workspaceName(for: key) ?? ""
                    ))
                }
            }
        }
        return results.sorted { $0.paneTitle < $1.paneTitle }
    }

    private func projectName(for id: UUID) -> String? {
        // Delegate to ProjectStore when available; fall back to nil.
        // If the store is held via a property, thread it through; otherwise this helper
        // stays minimal and the view supplies display strings from its environment.
        nil
    }

    private func workspaceName(for key: WorktreeKey) -> String? {
        worktreeStore?.worktree(projectID: key.projectID, worktreeID: key.worktreeID)?.name
    }
```

If display-name resolution needs `ProjectStore` and `AppState` does not already reference it, leave `projectName` returning `nil` here and compose the final label inside the view (which has both environments).

- [ ] **Step 8.2: Extend the tests**

Append to `Tests/MuxyTests/Sidebar/AwaitingPanesTests.swift`:

```swift
    func testAwaitingPanesReflectsAwaitingState() throws {
        let project = Project(name: "p", path: "/tmp/p")
        let persistence = InMemoryWorktreePersistence()
        let primary = Worktree(name: "default", path: "/tmp/p", isPrimary: true)
        try persistence.saveWorktrees([primary], projectID: project.id)
        let store = WorktreeStore(persistence: persistence, projects: [project])
        let appState = AppState()
        appState.worktreeStore = store
        let paneA = UUID()
        let paneB = UUID()
        let key = WorktreeKey(projectID: project.id, worktreeID: primary.id)
        appState.seedWorkspaceForTesting(key: key, paneID: paneA)
        appState.seedWorkspaceForTesting(key: key, paneID: paneB)

        XCTAssertEqual(appState.awaitingPanes.count, 0)
        _ = appState.updateAgentActivity(paneID: paneA, state: .awaiting)
        XCTAssertEqual(appState.awaitingPanes.map(\.paneID), [paneA])
        _ = appState.updateAgentActivity(paneID: paneB, state: .awaiting)
        XCTAssertEqual(Set(appState.awaitingPanes.map(\.paneID)), Set([paneA, paneB]))
        _ = appState.updateAgentActivity(paneID: paneA, state: .completed)
        XCTAssertEqual(appState.awaitingPanes.map(\.paneID), [paneB])
    }
```

Extend `seedWorkspaceForTesting` to append a second pane/tab when called twice with the same `key`, instead of recreating the whole graph.

- [ ] **Step 8.3: Run tests**

Run: `swift test --filter RoostTests.AwaitingPanesTests`
Expected: All tests pass.

- [ ] **Step 8.4: Full test run**

Run: `swift test`
Expected: All tests pass.

- [ ] **Step 8.5: Commit**

Run:
```
jj commit -m "feat(app-state): expose awaitingPanes computed summary"
```

---

### Task 9: `PendingAgentsBanner` view

**Files:**
- Create: `Muxy/Views/Sidebar/PendingAgentsBanner.swift`

- [ ] **Step 9.1: Create the view**

Create `Muxy/Views/Sidebar/PendingAgentsBanner.swift`:

```swift
import SwiftUI

struct PendingAgentsBanner: View {
    @Environment(AppState.self) private var appState
    @State private var showingPopover = false

    var body: some View {
        let awaiting = appState.awaitingPanes
        if awaiting.isEmpty {
            EmptyView()
        } else {
            Button {
                showingPopover = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.yellow)
                    Text("\(awaiting.count) agent\(awaiting.count == 1 ? "" : "s") awaiting")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.yellow.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingPopover, arrowEdge: .trailing) {
                PendingAgentsPopover(summaries: awaiting) { paneID in
                    showingPopover = false
                    focus(paneID: paneID)
                }
                .frame(minWidth: 240)
            }
        }
    }

    private func focus(paneID: UUID) {
        appState.focusPane(paneID: paneID)
    }
}

private struct PendingAgentsPopover: View {
    let summaries: [AwaitingPaneSummary]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(summaries) { summary in
                Button {
                    onSelect(summary.paneID)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.paneTitle)
                            .font(.system(size: 12, weight: .semibold))
                        let subtitle = [summary.projectName, summary.workspaceName]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 9.2: Provide `focusPane` on `AppState`**

Search `Muxy/Models/AppState.swift` for an existing method that navigates focus to a specific pane (candidates: `selectTab`, `focusPane`, `activatePane`). If a suitable one exists, rename the call in `PendingAgentsBanner` to match.

If none exists, add:

```swift
    func focusPane(paneID: UUID) {
        for (key, root) in workspaceRoots {
            for area in root.allAreas() {
                for tab in area.tabs {
                    guard let pane = tab.content.pane, pane.id == paneID else { continue }
                    dispatch(.selectProject(projectID: key.projectID))
                    dispatch(.selectWorkspace(key: key))
                    dispatch(.selectTab(tabID: tab.id, in: key))
                    return
                }
            }
        }
    }
```

Replace `dispatch(.selectProject(...))` / `dispatch(.selectWorkspace(...))` / `dispatch(.selectTab(...))` with the actual action cases defined in `WorkspaceReducer`. The enum case names are discoverable by searching `case select` inside the reducer file.

- [ ] **Step 9.3: Build**

Run: `swift build`
Expected: Success.

- [ ] **Step 9.4: Commit**

Run:
```
jj commit -m "feat(sidebar): add PendingAgentsBanner with navigation popover"
```

---

### Task 10: `NewWorkspaceButton` view

**Files:**
- Create: `Muxy/Views/Sidebar/NewWorkspaceButton.swift`

- [ ] **Step 10.1: Create the view**

Create `Muxy/Views/Sidebar/NewWorkspaceButton.swift`:

```swift
import SwiftUI

struct NewWorkspaceButton: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    let expanded: Bool
    @State private var showCreateSheet = false

    private var targetProject: Project? {
        guard let id = appState.activeProjectID, id != Project.scratchID else { return nil }
        return projectStore.projects.first { $0.id == id }
    }

    var body: some View {
        Button {
            guard targetProject != nil else { return }
            showCreateSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                if expanded {
                    Text("New Workspace")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(targetProject == nil ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(targetProject == nil)
        .help(targetProject == nil ? "Select a project first" : "New Workspace in \(targetProject?.name ?? "")")
        .popover(isPresented: $showCreateSheet, arrowEdge: .trailing) {
            if let project = targetProject {
                CreateWorktreeSheet(project: project) { _ in
                    showCreateSheet = false
                }
            }
        }
    }
}
```

- [ ] **Step 10.2: Build**

Run: `swift build`
Expected: Success.

- [ ] **Step 10.3: Commit**

Run:
```
jj commit -m "feat(sidebar): add NewWorkspaceButton bound to activeProjectID"
```

---

### Task 11: Restructure sidebar body and pin top region

**Files:**
- Modify: `Muxy/Views/Sidebar.swift`

- [ ] **Step 11.1: Remove Scratch from the ScrollView**

In `projectList`, delete the top block inside the `LazyVStack`:

```swift
                if isWide {
                    ScratchRow()
                } else {
                    ScratchCollapsedRow()
                }
```

- [ ] **Step 11.2: Add a new `topFixedBar` computed view**

Inside `Sidebar`, add:

```swift
    private var topFixedBar: some View {
        VStack(spacing: 4) {
            if isWide {
                ScratchRow()
            } else {
                ScratchCollapsedRow()
            }
            PendingAgentsBanner()
            NewWorkspaceButton(expanded: isWide)
        }
        .padding(.horizontal, isWide ? 6 : 8)
        .padding(.vertical, 4)
        .background(MuxyTheme.bg)
    }
```

- [ ] **Step 11.3: Wire `topFixedBar` into `body`**

Replace the current `body` layout of `Sidebar`:

```swift
    var body: some View {
        VStack(spacing: 0) {
            topFixedBar
                .fixedSize(horizontal: false, vertical: true)

            projectList
                .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                .clipped()

            addProjectBar

            SidebarFooter(expanded: isWide)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .frame(width: isHidden ? 0 : (isWide ? SidebarLayout.expandedWidth : SidebarLayout.collapsedWidth))
        .opacity(isHidden ? 0 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            toggleExpanded()
        }
    }
```

- [ ] **Step 11.4: Manual verification**

Run: `swift build`
Expected: Success.

Run: `swift run Roost`
Expected:
- Scratch row pinned at the top, not scrolling with project list.
- "+ Workspace" button pinned below Scratch, disabled (greyed) when no project is active.
- With no awaiting agents, banner is hidden (no blank gap).
- Project list scrolls beneath the fixed top region.
- Add Project remains at the bottom as before.

Close the app when confirmed.

- [ ] **Step 11.5: Commit**

Run:
```
jj commit -m "feat(sidebar): pin Scratch, pending banner, and new-workspace to top region"
```

---

### Task 12: Remove inline `ExpandedNewWorktreeButton` usage

**Files:**
- Modify: `Muxy/Views/Sidebar/ExpandedProjectRow.swift`

- [ ] **Step 12.1: Remove the inline call**

Delete `ExpandedProjectRow.swift:310-312`:

```swift
            ExpandedNewWorktreeButton {
                presentCreateWorktreeSheet()
            }
```

The `.popover(isPresented: $showCreateWorktreeSheet)` attached to this button migrates: it must stay attached to some view inside `worktreeList` to keep the context-menu entry and the `requestCreateWorkspaceForAgent` notification path working. Reattach the `.popover` to the enclosing `VStack` of `worktreeList` (the outermost container returned by that computed property), so that presentation still flows from `showCreateWorktreeSheet = true` regardless of which button triggered it.

Concretely, move the `.popover(...)` modifier from the removed `ExpandedNewWorktreeButton` call site to the end of the `worktreeList` view's outer container.

- [ ] **Step 12.2: Remove the now-unused helper struct (conditional)**

Run: `grep -n "ExpandedNewWorktreeButton" Muxy/`
Expected: Only the definition at `ExpandedProjectRow.swift:875` remains (no callers).

If no callers exist, delete the `private struct ExpandedNewWorktreeButton: View { … }` block. If any caller exists (there should be none after Step 12.1), leave the struct in place.

- [ ] **Step 12.3: Build and smoke test**

Run: `swift build`
Expected: Success.

Run: `swift run Roost`
Expected:
- Expanded project rows no longer show the inline "+ New Workspace" button below their worktree list.
- Right-click on a project row still shows "New Workspace…" which opens the sheet.
- Top-pinned `+ Workspace` button also opens the sheet for the currently active project.

Close the app when confirmed.

- [ ] **Step 12.4: Commit**

Run:
```
jj commit -m "refactor(sidebar): remove inline ExpandedNewWorktreeButton in favor of pinned entry"
```

---

### Task 13: Right-click sort toggle

**Files:**
- Modify: `Muxy/Views/Sidebar.swift`

- [ ] **Step 13.1: Attach context menu to `projectList`**

Inside `projectList`, wrap the `ScrollView` in a container that carries a context menu. Add right after the `LazyVStack { … }` content, before the closing `.coordinateSpace(name: "sidebar")`:

```swift
        .contextMenu {
            Picker("Sort", selection: Binding(
                get: { projectSortMode },
                set: { projectSortModeRaw = $0.rawValue }
            )) {
                ForEach(ProjectSortMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        }
```

`Picker` inside `.contextMenu` renders as a checkmarked submenu on macOS and keeps the two modes mutually exclusive.

- [ ] **Step 13.2: Manual verification**

Run: `swift run Roost`
Expected:
- Right-click in empty sidebar space opens a context menu with a "Sort" submenu listing "Manual" (checked) and "Recently Active".
- Switching to "Recently Active" re-orders the project list.
- Dragging a project while "Recently Active" is selected does nothing.
- Switching back to "Manual" re-enables drag reorder.

Close the app when confirmed.

- [ ] **Step 13.3: Commit**

Run:
```
jj commit -m "feat(sidebar): add right-click Sort toggle in project list"
```

---

### Task 14: Lint, format, and final integration

**Files:**
- No direct edits, but auto-fixers may touch formatting.

- [ ] **Step 14.1: Run the project's checks script**

Run: `scripts/checks.sh --fix`
Expected: Passes. The script runs `swiftformat` and `swiftlint --strict` with a pinned tool version and its own `$TMPDIR/roost-spm-build-*` path.

- [ ] **Step 14.2: Full test run**

Run: `swift test`
Expected: All tests pass, no warnings about unused symbols introduced in this plan.

- [ ] **Step 14.3: Exploratory UI pass**

Run: `swift run Roost`
Check all items together:
- Top region order top-to-bottom: Scratch → Pending banner (hidden when zero) → + Workspace.
- Pending banner: create an agent in awaiting state (use an existing Claude/Codex agent pane that asks for input) and verify the count, popover, and jump behavior. Confirm `awaitingPanes` clears when the agent transitions out.
- Sort mode: switch via right-click, verify drag gating in each mode, verify recency-based promotion after interacting with agents in different projects.
- + Workspace: disabled when no project active, enabled and targets the focused project when one is active.
- Legacy: opening a pre-existing persisted `worktree.json` still loads (no `lastActiveAt` field).

Record any regressions in the task checklist as bugs to fix before merging.

Close the app when satisfied.

- [ ] **Step 14.4: Commit if `scripts/checks.sh --fix` produced changes**

Run:
```
jj st
```

If changes exist:
```
jj commit -m "chore(sidebar): swiftformat / swiftlint pass"
```

If clean, skip the commit.

- [ ] **Step 14.5: Squash WIP history (optional)**

Review with:
```
jj log -r "::@"
```

If the branch history has too many small WIP commits and the user prefers a tighter series, use `jj squash -m "…"` to combine adjacent revisions. Do not squash across commits that belong to unrelated features. The user is the final arbiter; ask before squashing.

- [ ] **Step 14.6: Hand back to the user**

Summarize: the branch contains the commit series ending at the current `@-`, all tests pass, UI smoke tests pass. Do not push; the user decides when/where to push per the project's VCS policy.

---

## Self-Review

Coverage of spec sections against plan tasks:

- Layout骨架 (spec §Architecture → layout diagram) → Task 11.
- Worktree.lastActiveAt (spec §Data model changes) → Task 2.
- Project derived lastActiveAt (spec §Data model changes) → Task 6 (service encapsulates the derivation).
- projectSortMode @AppStorage (spec §Data model changes) → Tasks 5, 7, 13.
- Single activity source = updateAgentActivity (spec §Activity tracking) → Task 4.
- markActive + debounced save (spec §Activity tracking) → Task 3.
- Sort pipeline partitioned at 4h threshold (spec §Sort pipeline) → Task 6 tests + Task 7 integration.
- Drag disabled in .active mode (spec §Project drag behavior) → Task 7.2.
- Pending banner + computed awaitingPanes (spec §Pending banner) → Tasks 8 and 9.
- +Workspace button bound to activeProjectID, disabled without focus (spec §+ Workspace button) → Task 10 + Task 11.
- Remove inline ExpandedNewWorktreeButton, keep context-menu entry (spec §+ Workspace button — revised) → Task 12.
- Right-click sort toggle; no settings page (spec §Right-click toggle) → Task 13.
- Persistence through existing WorktreeStore JSON (spec §Persistence) → Task 2 (Codable) + Task 3 (save path).
- Tests for sorting / markActive / awaiting panes (spec §Testing) → Tasks 2, 3, 6, 8.

Risk / deferred items flagged inline at Steps 4.1, 4.3, 8.1, 9.2, 12.1 where the exact names of pre-existing helpers (`WorktreePersisting` fake, seed helper, reducer action cases, popover host container) must be confirmed by reading the surrounding code before pasting the example code.

No placeholders remain in step bodies; every code block is complete Swift.
