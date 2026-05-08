# Activity Log and Awaiting State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename `AgentActivityState.needsInput` to `.awaiting` (orange) to reflect "completed and awaiting user continuation" semantics, and add a separate persistent `ActivityLogStore` that records every agent activity transition independent of `NotificationStore` focus filtering.

**Architecture:** Phase B builds on Phase A and lands in a child jj revision. Phase A is a renaming refactor plus a small state-machine change: enum case `needsInput` becomes `awaiting` while keeping the raw value `"needsInput"` so that on-disk `WorkspaceSnapshot` JSON keeps decoding unchanged; the `completed → awaiting` transition is unsuppressed so that a `Notification` hook arriving after a Stop hook can turn the badge orange (the `exited → awaiting` suppression is preserved because exited is terminal). The badge color flips from `MuxyTheme.diffRemoveFg` (red) to `MuxyTheme.warning` (orange). Phase B introduces a new `MuxyShared/Agent/AgentActivityEvent` model and a `Muxy/Services/ActivityLogStore` that `AppState.updateAgentActivity` appends to whenever the activity state actually changes. The store debounces saves to `~/Library/Application Support/Roost/activity-log.json` with a 1000-event ring buffer.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, `CodableFileStore`, jj for VCS.

---

## Scope And Boundaries

- Phase A has two user-visible changes: badge color flips red → orange, and `completed` panes now transition to `awaiting` when a `Notification` hook arrives (previously suppressed).
- Phase B does not change any existing surface; it adds a new on-disk log read by no UI yet. UI consumers come in a follow-up.
- Hook scripts and socket protocol are not changed. `claude_hook:needs_input` keeps mapping to the same enum case (now spelled `.awaiting`) via the preserved raw value.
- Phase B depends on Phase A. The `.awaiting` enum case introduced in A is referenced throughout B's tests and source. Land A first, then stack B on top.

## File Structure

### Phase A files

- Modify `MuxyShared/Agent/AgentActivityState.swift`
  - Rename `case needsInput` to `case awaiting = "needsInput"`. Keep raw value to preserve persistence compatibility.
  - Update `sidebarLabel`, `accessibilityLabel`.
- Modify `Muxy/Services/AgentActivity/AgentActivitySocketEvent.swift`
  - Map `needs_input`, `needsInput`, `permission` suffix strings to `.awaiting`.
- Modify `Muxy/Models/AppState.swift`
  - Replace every `.needsInput` literal with `.awaiting` (six sites in `updateAgentActivity`).
- Modify `Muxy/Models/TerminalPaneState.swift`
  - Replace `case .needsInput` with `case .awaiting` in `acknowledgeUserInteraction`.
- Modify `Muxy/Views/Sidebar/AgentActivityStatusIcon.swift`
  - Change color for `.awaiting` from `MuxyTheme.diffRemoveFg` to `MuxyTheme.warning`.
- Modify `Muxy/Views/Sidebar/AgentActivityBadge.swift`
  - Update icon, foreground, background, border for `.awaiting` to use `MuxyTheme.warning`.
- Modify `Muxy/Views/Sidebar/SessionRow.swift`
  - Replace `.needsInput` with `.awaiting`.
- Modify `Muxy/Views/Sidebar/SidebarAgentActivityResolver.swift`
  - Replace `.needsInput` with `.awaiting` in priority array and switch cases.
- Modify `Muxy/Views/Sidebar/ExpandedProjectRow.swift`
  - Rename local `ExpandedWorktreeRowBackgroundKind.needsInput` to `.awaiting`. Update `resolve(dominantState:)` switch.
- Modify all tests that reference `.needsInput`:
  - `Tests/MuxyTests/Agent/AgentActivityStateTests.swift`
  - `Tests/MuxyTests/Sidebar/AgentActivityStatusPulseStyleTests.swift`
  - `Tests/MuxyTests/Models/AppStateAgentActivityTests.swift`
  - `Tests/MuxyTests/Models/TerminalPaneActivityStateTests.swift`
  - `Tests/MuxyTests/Sidebar/SidebarAgentActivityResolverTests.swift`
  - `Tests/MuxyTests/Sidebar/ExpandedProjectRowSelectionTests.swift`
  - `Tests/MuxyTests/Workspace/PaneTabStripSnapshotTests.swift`
  - `Tests/MuxyTests/Services/AgentActivitySocketEventTests.swift`

### Phase B files

- Create `MuxyShared/Agent/AgentActivityEvent.swift`
- Create `Muxy/Services/ActivityLogStore.swift`
- Modify `Muxy/Models/AppState.swift`
  - Inject `ActivityLogStore`. Append on real state changes inside `updateAgentActivity`.
- Modify `Muxy/RoostApp.swift` or wherever `AppState` is constructed
  - Wire the live `ActivityLogStore` instance in.
- Create `Tests/MuxyTests/Services/ActivityLogStoreTests.swift`
- Modify `Tests/MuxyTests/Models/AppStateAgentActivityTests.swift`
  - Add a stub `ActivityLogStoring` and assert append behavior on the existing transition tests.

---

# Phase A: Awaiting State

## Task A1: Rename enum case and raw labels

**Files:**
- Modify: `MuxyShared/Agent/AgentActivityState.swift`
- Modify: `Tests/MuxyTests/Agent/AgentActivityStateTests.swift`

- [ ] **Step 1: Update the enum and its labels**

Replace the entire contents of `MuxyShared/Agent/AgentActivityState.swift`:

```swift
import Foundation

public enum AgentActivityState: String, Sendable, Codable, Hashable, CaseIterable {
    case running
    case awaiting = "needsInput"
    case idle
    case completed
    case exited

    public var sidebarLabel: String {
        switch self {
        case .running: "RUN"
        case .awaiting: "WAIT"
        case .idle: "IDLE"
        case .completed: "DONE"
        case .exited: "EXIT"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .running: "Running"
        case .awaiting: "Awaiting input"
        case .idle: "Idle"
        case .completed: "Completed"
        case .exited: "Exited"
        }
    }
}
```

- [ ] **Step 2: Update `AgentActivityStateTests.swift`**

Replace the entire file with:

```swift
import Foundation
import MuxyShared
import Testing

@Suite("AgentActivityState")
struct AgentActivityStateTests {
    @Test("Codable round-trips all cases")
    func codableRoundTrip() throws {
        let original = AgentActivityState.allCases
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([AgentActivityState].self, from: data)
        #expect(decoded == original)
    }

    @Test("raw values are stable")
    func rawValues() {
        #expect(AgentActivityState.running.rawValue == "running")
        #expect(AgentActivityState.awaiting.rawValue == "needsInput")
        #expect(AgentActivityState.idle.rawValue == "idle")
        #expect(AgentActivityState.completed.rawValue == "completed")
        #expect(AgentActivityState.exited.rawValue == "exited")
    }

    @Test("legacy needsInput rawValue decodes into awaiting")
    func legacyRawValueDecodes() throws {
        let json = #""needsInput""#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AgentActivityState.self, from: json)
        #expect(decoded == .awaiting)
    }

    @Test("sidebar labels are compact")
    func sidebarLabels() {
        #expect(AgentActivityState.running.sidebarLabel == "RUN")
        #expect(AgentActivityState.awaiting.sidebarLabel == "WAIT")
        #expect(AgentActivityState.idle.sidebarLabel == "IDLE")
        #expect(AgentActivityState.completed.sidebarLabel == "DONE")
        #expect(AgentActivityState.exited.sidebarLabel == "EXIT")
    }

    @Test("accessibility labels are human readable")
    func accessibilityLabels() {
        #expect(AgentActivityState.running.accessibilityLabel == "Running")
        #expect(AgentActivityState.awaiting.accessibilityLabel == "Awaiting input")
        #expect(AgentActivityState.idle.accessibilityLabel == "Idle")
        #expect(AgentActivityState.completed.accessibilityLabel == "Completed")
        #expect(AgentActivityState.exited.accessibilityLabel == "Exited")
    }
}
```

- [ ] **Step 3: Verify the test fails on stale call sites**

Run: `swift test --filter RoostTests.AgentActivityStateTests`
Expected: FAIL — every `.needsInput` reference in the rest of the codebase fails to compile, because the case has been renamed.

- [ ] **Step 4: Do not commit yet**

Tests will not compile until Task A2 finishes the rename across call sites. Move on to Task A2.

## Task A2: Replace `.needsInput` literals across source files

**Files:**
- Modify: `Muxy/Services/AgentActivity/AgentActivitySocketEvent.swift`
- Modify: `Muxy/Models/AppState.swift:260-286`
- Modify: `Muxy/Models/TerminalPaneState.swift:94`
- Modify: `Muxy/Views/Sidebar/SessionRow.swift:81`
- Modify: `Muxy/Views/Sidebar/SidebarAgentActivityResolver.swift:86,93`
- Modify: `Muxy/Views/Sidebar/ExpandedProjectRow.swift:645,650-651,809`

- [ ] **Step 1: Update socket event parser**

In `Muxy/Services/AgentActivity/AgentActivitySocketEvent.swift`, change the `activityState(from:)` switch:

```swift
case "needs_input",
     "needsInput",
     "permission":
    .awaiting
```

- [ ] **Step 2: Update AppState transitions and unsuppress completed → awaiting**

In `Muxy/Models/AppState.swift`, inside `updateAgentActivity(paneID:state:)` (around line 260-286), do two things in the same edit:

1. Rename every `.needsInput` literal to `.awaiting`.
2. Remove `pane.activityState == .completed` from the second suppression guard so a `Notification` hook arriving after a Stop hook can transition `completed → awaiting`. Keep the `.exited` arm — exited panes must stay terminal.

The full updated body:

```swift
@discardableResult
func updateAgentActivity(paneID: UUID, state: AgentActivityState) -> Bool {
    for root in workspaceRoots.values {
        for area in root.allAreas() {
            for tab in area.tabs {
                guard let pane = tab.content.pane, pane.id == paneID else { continue }
                guard pane.activityState != state else { return true }
                if state == .completed,
                   pane.activityState == .awaiting || pane.activityState == .exited
                {
                    return true
                }
                if state == .awaiting,
                   pane.activityState == .exited
                {
                    return true
                }
                if state == .awaiting {
                    pane.previousActivityState = pane.activityState
                }
                pane.activityState = state
                advanceAgentActivityRevision()
                return true
            }
        }
    }
    return false
}
```

- [ ] **Step 3: Update TerminalPaneState.acknowledgeUserInteraction**

In `Muxy/Models/TerminalPaneState.swift`, replace `case .needsInput:` with `case .awaiting:` in `acknowledgeUserInteraction()`. The full method body:

```swift
@discardableResult
func acknowledgeUserInteraction() -> Bool {
    guard agentKind != .terminal else { return false }
    switch activityState {
    case .completed:
        activityState = .idle
        previousActivityState = nil
        return true
    case .awaiting:
        activityState = previousActivityState ?? .idle
        previousActivityState = nil
        return true
    default:
        return false
    }
}
```

- [ ] **Step 4: Update SessionRow**

In `Muxy/Views/Sidebar/SessionRow.swift:81`, change `activityState == .needsInput` to `activityState == .awaiting`.

- [ ] **Step 5: Update SidebarAgentActivityResolver**

In `Muxy/Views/Sidebar/SidebarAgentActivityResolver.swift`:
- Line 86: change priority array `[.needsInput, ...]` to `[.awaiting, ...]`.
- Line 93: change `case .needsInput,` to `case .awaiting,`.

Search and replace `.needsInput` with `.awaiting` throughout the file.

- [ ] **Step 6: Update ExpandedProjectRow local enum**

In `Muxy/Views/Sidebar/ExpandedProjectRow.swift`, rename the local case in `ExpandedWorktreeRowBackgroundKind`:

```swift
enum ExpandedWorktreeRowBackgroundKind: Equatable {
    case neutral
    case hover
    case awaiting
    case completed

    static func resolve(dominantState: AgentActivityState?, hovered: Bool) -> ExpandedWorktreeRowBackgroundKind {
        switch dominantState {
        case .awaiting:
            .awaiting
        case .completed:
            .completed
        case .running,
             .idle,
             .exited,
             nil:
            hovered ? .hover : .neutral
        }
    }
}
```

Then search for any remaining `.needsInput` in the same file (around line 809) and replace with `.awaiting`.

- [ ] **Step 7: Build and run all tests except color-specific ones**

Run: `swift build`
Expected: PASS

Run: `swift test --filter RoostTests.AgentActivityStateTests`
Run: `swift test --filter RoostTests.AppStateAgentActivityTests`
Run: `swift test --filter RoostTests.TerminalPaneActivityStateTests`
Run: `swift test --filter RoostTests.AgentActivitySocketEventTests`
Run: `swift test --filter RoostTests.SidebarAgentActivityResolverTests`

Expected: the test target fails to compile because the test files still reference the old `.needsInput` name. That is fixed in Step 8 below.

- [ ] **Step 8: Update tests still referencing `.needsInput`**

In each of these files, replace `.needsInput` with `.awaiting`:

- `Tests/MuxyTests/Sidebar/AgentActivityStatusPulseStyleTests.swift`
- `Tests/MuxyTests/Models/AppStateAgentActivityTests.swift`
- `Tests/MuxyTests/Models/TerminalPaneActivityStateTests.swift`
- `Tests/MuxyTests/Sidebar/SidebarAgentActivityResolverTests.swift`
- `Tests/MuxyTests/Sidebar/ExpandedProjectRowSelectionTests.swift`
- `Tests/MuxyTests/Workspace/PaneTabStripSnapshotTests.swift`
- `Tests/MuxyTests/Services/AgentActivitySocketEventTests.swift`

Also rename test function names that contain `needsInput` to use `awaiting` (e.g. `donePreservesNeedsInput` → `donePreservesAwaiting`, `needsInputRestoresPreviousState` → `awaitingRestoresPreviousState`, `needsInputTransitionsRunning` → `awaitingTransitionsRunning`, `needsInputPreservesExited` → `awaitingPreservesExited`, `needsInputWithoutPreviousDefaultsToIdle` → `awaitingWithoutPreviousDefaultsToIdle`, `needsInput` socket-event test → `awaiting`).

In `Tests/MuxyTests/Models/AppStateAgentActivityTests.swift`, also flip the assertion in the test currently named `needsInputPreservesCompleted` (the suppression you removed in Task A2 Step 2). Rename it and rewrite it as:

```swift
@Test("awaiting transitions completed to awaiting (idle ping after stop)")
func awaitingTransitionsCompleted() {
    let appState = makeAppState()
    let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
    let area = TabArea(projectPath: "/tmp/wt")
    area.createAgentTab(kind: .codex)
    let pane = area.activeTab!.content.pane!
    pane.activityState = .completed
    appState.workspaceRoots[key] = .tabArea(area)

    let revisionBefore = appState.agentActivityRevision
    let updated = appState.updateAgentActivity(paneID: pane.id, state: .awaiting)

    #expect(updated == true)
    #expect(pane.activityState == .awaiting)
    #expect(pane.previousActivityState == .completed)
    #expect(appState.agentActivityRevision == revisionBefore + 1)
}
```

This is the user-visible behavior change: `completed → awaiting` is now allowed.

- [ ] **Step 9: Run the full test suite**

Run: `swift test`
Expected: PASS

- [ ] **Step 10: Run lint**

Run: `scripts/checks.sh`
Expected: PASS

- [ ] **Step 11: Commit Phase A first half (rename only, color unchanged)**

This commit should compile and pass tests but the badge is still red. Color flip is its own commit so a future bisector can test the rename alone.

```bash
jj commit -m "refactor(activity): rename AgentActivityState.needsInput to .awaiting"
```

## Task A3: Flip the badge color from red to orange

**Files:**
- Modify: `Muxy/Views/Sidebar/AgentActivityStatusIcon.swift:99-107`
- Modify: `Muxy/Views/Sidebar/AgentActivityBadge.swift:38-92`
- Add: `Tests/MuxyTests/Sidebar/AgentActivityStatusPulseStyleTests.swift` (new color assertion)

- [ ] **Step 1: Confirm no existing color test exists**

The color lives inside the SwiftUI view body and is not exposed via `AgentActivityStatusPulseStyle`, so it has no unit-level harness. We rely on a manual visual check at Step 5.

Run:

```
rg -n "MuxyTheme.diffRemoveFg|MuxyTheme.warning" Tests/MuxyTests/
```

Expected: no matches.

- [ ] **Step 2: Update `AgentActivityStatusIcon.swift` color**

In `Muxy/Views/Sidebar/AgentActivityStatusIcon.swift`, in `AgentActivityPulsingStatusIcon.color` (around line 99-107), change:

```swift
private var color: Color {
    switch style.state {
    case .running: MuxyTheme.accent
    case .awaiting: MuxyTheme.warning
    case .completed: MuxyTheme.diffAddFg
    case .idle: MuxyTheme.fgDim.opacity(0.45)
    case .exited: MuxyTheme.fgDim
    }
}
```

- [ ] **Step 3: Update `AgentActivityBadge.swift` colors**

In `Muxy/Views/Sidebar/AgentActivityBadge.swift`, replace every `MuxyTheme.diffRemoveFg` reference associated with `.awaiting` (in `foreground`, `background`, `border`) with `MuxyTheme.warning` and matching opacities. Final relevant slices:

```swift
private var foreground: Color {
    switch state {
    case .running: MuxyTheme.accent
    case .awaiting: MuxyTheme.warning
    case .idle: MuxyTheme.fgMuted
    case .completed: MuxyTheme.diffAddFg
    case .exited: MuxyTheme.fgDim
    }
}

private var background: AnyShapeStyle {
    switch state {
    case .awaiting:
        AnyShapeStyle(LinearGradient(
            colors: [
                MuxyTheme.warning.opacity(0.28),
                MuxyTheme.warning.opacity(0.12),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
    case .completed:
        AnyShapeStyle(MuxyTheme.diffAddFg.opacity(0.14))
    case .running:
        AnyShapeStyle(MuxyTheme.accent.opacity(0.12))
    case .idle:
        AnyShapeStyle(MuxyTheme.surface)
    case .exited:
        AnyShapeStyle(MuxyTheme.surface)
    }
}

private var border: Color {
    switch state {
    case .awaiting: MuxyTheme.warning.opacity(0.22)
    case .completed: MuxyTheme.diffAddFg.opacity(0.2)
    case .running: MuxyTheme.accent.opacity(0.18)
    case .idle,
         .exited: MuxyTheme.border
    }
}
```

- [ ] **Step 4: Run all tests and lint**

Run: `swift test`
Run: `scripts/checks.sh`
Expected: PASS

- [ ] **Step 5: Manual UI verification**

Run: `swift run Roost`
Expected:
- Trigger Claude `Notification` hook (or wait for an agent idle ping).
- The sidebar dot for that pane breathes orange (`MuxyTheme.warning`), not red.
- Hovering shows the help text "Awaiting input".

Capture a screenshot for the PR.

- [ ] **Step 6: Commit Phase A second half**

```bash
jj commit -m "feat(activity): paint awaiting state orange (MuxyTheme.warning)"
```

---

# Phase B: Activity Log

## Task B1: Define `AgentActivityEvent` model

**Files:**
- Create: `MuxyShared/Agent/AgentActivityEvent.swift`
- Create: `Tests/MuxyTests/Agent/AgentActivityEventTests.swift`

- [ ] **Step 1: Write a failing model test**

Create `Tests/MuxyTests/Agent/AgentActivityEventTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@Suite("AgentActivityEvent")
struct AgentActivityEventTests {
    @Test("encodes and decodes round-trip with all fields")
    func roundTrip() throws {
        let event = AgentActivityEvent(
            id: UUID(),
            paneID: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            from: .running,
            to: .awaiting,
            sourceType: "claude_hook"
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentActivityEvent.self, from: data)

        #expect(decoded == event)
    }

    @Test("decodes legacy events that omit projectID, worktreeID, sourceType")
    func decodesPartialLegacyEvent() throws {
        let json = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "paneID": "66666666-7777-8888-9999-AAAAAAAAAAAA",
            "timestamp": 1700000000,
            "to": "running"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AgentActivityEvent.self, from: json)

        #expect(decoded.from == nil)
        #expect(decoded.to == .running)
        #expect(decoded.projectID == nil)
        #expect(decoded.worktreeID == nil)
        #expect(decoded.sourceType == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RoostTests.AgentActivityEventTests`
Expected: FAIL — `AgentActivityEvent` is undefined.

- [ ] **Step 3: Implement `AgentActivityEvent`**

Create `MuxyShared/Agent/AgentActivityEvent.swift`:

```swift
import Foundation

public struct AgentActivityEvent: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let paneID: UUID
    public let projectID: UUID?
    public let worktreeID: UUID?
    public let timestamp: Date
    public let from: AgentActivityState?
    public let to: AgentActivityState
    public let sourceType: String?

    public init(
        id: UUID = UUID(),
        paneID: UUID,
        projectID: UUID? = nil,
        worktreeID: UUID? = nil,
        timestamp: Date = Date(),
        from: AgentActivityState? = nil,
        to: AgentActivityState,
        sourceType: String? = nil
    ) {
        self.id = id
        self.paneID = paneID
        self.projectID = projectID
        self.worktreeID = worktreeID
        self.timestamp = timestamp
        self.from = from
        self.to = to
        self.sourceType = sourceType
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter RoostTests.AgentActivityEventTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(activity): add AgentActivityEvent model"
```

## Task B2: Build `ActivityLogStore`

**Files:**
- Create: `Muxy/Services/ActivityLogStore.swift`
- Create: `Tests/MuxyTests/Services/ActivityLogStoreTests.swift`

- [ ] **Step 1: Write failing store tests**

Create `Tests/MuxyTests/Services/ActivityLogStoreTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("ActivityLogStore")
struct ActivityLogStoreTests {
    @Test("append adds events in chronological order")
    func appendInOrder() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-log-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ActivityLogStore(fileURL: url, maxEvents: 1000)
        let paneID = UUID()
        store.append(AgentActivityEvent(paneID: paneID, to: .running))
        store.append(AgentActivityEvent(paneID: paneID, from: .running, to: .completed))

        #expect(store.events.count == 2)
        #expect(store.events.first?.to == .running)
        #expect(store.events.last?.to == .completed)
    }

    @Test("trims to maxEvents")
    func trimsToMax() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-log-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ActivityLogStore(fileURL: url, maxEvents: 2)
        let paneID = UUID()
        for _ in 0 ..< 5 {
            store.append(AgentActivityEvent(paneID: paneID, to: .running))
        }

        #expect(store.events.count == 2)
    }

    @Test("loads previously saved events on init")
    func loadsFromDisk() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-log-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = ActivityLogStore(fileURL: url, maxEvents: 1000)
        let paneID = UUID()
        first.append(AgentActivityEvent(paneID: paneID, to: .running))
        first.flush()

        let second = ActivityLogStore(fileURL: url, maxEvents: 1000)
        #expect(second.events.count == 1)
        #expect(second.events.first?.paneID == paneID)
    }

    @Test("eventsForPane filters by pane id")
    func eventsForPane() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-log-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ActivityLogStore(fileURL: url, maxEvents: 1000)
        let paneA = UUID()
        let paneB = UUID()
        store.append(AgentActivityEvent(paneID: paneA, to: .running))
        store.append(AgentActivityEvent(paneID: paneB, to: .running))
        store.append(AgentActivityEvent(paneID: paneA, from: .running, to: .completed))

        let filtered = store.events(for: paneA)
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.paneID == paneA })
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter RoostTests.ActivityLogStoreTests`
Expected: FAIL — `ActivityLogStore` is undefined.

- [ ] **Step 3: Implement `ActivityLogStore`**

Create `Muxy/Services/ActivityLogStore.swift`:

```swift
import Foundation
import MuxyShared
import os

private let logger = Logger(subsystem: "app.muxy", category: "ActivityLogStore")

protocol ActivityLogStoring: AnyObject {
    func append(_ event: AgentActivityEvent)
}

@MainActor
@Observable
final class ActivityLogStore: ActivityLogStoring {
    private(set) var events: [AgentActivityEvent] = []

    private let store: CodableFileStore<[AgentActivityEvent]>
    private let maxEvents: Int
    private var saveTask: Task<Void, Never>?

    static let defaultFileURL: URL = MuxyFileStorage.fileURL(filename: "activity-log.json")
    static let defaultMaxEvents = 1000

    init(
        fileURL: URL = ActivityLogStore.defaultFileURL,
        maxEvents: Int = ActivityLogStore.defaultMaxEvents
    ) {
        self.store = CodableFileStore<[AgentActivityEvent]>(fileURL: fileURL)
        self.maxEvents = maxEvents
        self.events = Self.loadFromDisk(store: store, maxEvents: maxEvents)
    }

    func append(_ event: AgentActivityEvent) {
        events.append(event)
        trim()
        scheduleSave()
    }

    func events(for paneID: UUID) -> [AgentActivityEvent] {
        events.filter { $0.paneID == paneID }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        saveToDisk()
    }

    private func trim() {
        guard events.count > maxEvents else { return }
        events = Array(events.suffix(maxEvents))
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveToDisk()
        }
    }

    private func saveToDisk() {
        do {
            try store.save(events)
        } catch {
            logger.error("Failed to save activity log: \(error.localizedDescription)")
        }
    }

    private static func loadFromDisk(
        store: CodableFileStore<[AgentActivityEvent]>,
        maxEvents: Int
    ) -> [AgentActivityEvent] {
        do {
            let loaded = try store.load() ?? []
            return Array(loaded.suffix(maxEvents))
        } catch {
            logger.error("Failed to load activity log: \(error.localizedDescription)")
            return []
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter RoostTests.ActivityLogStoreTests`
Expected: PASS.

- [ ] **Step 5: Run lint**

Run: `scripts/checks.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(activity): add ActivityLogStore with file-backed ring buffer"
```

## Task B3: Wire `ActivityLogStore` into `AppState.updateAgentActivity`

**Files:**
- Modify: `Muxy/Models/AppState.swift:116-130, 260-286`
- Modify: `Muxy/MuxyApp.swift:27-33` (only production `AppState(` call site)
- Modify: `Tests/MuxyTests/Models/AppStateAgentActivityTests.swift`

- [ ] **Step 1: Add a failing test that asserts log append on transition**

In `Tests/MuxyTests/Models/AppStateAgentActivityTests.swift`, add at the top of the file:

```swift
@MainActor
private final class FakeActivityLogStore: ActivityLogStoring {
    var appended: [AgentActivityEvent] = []
    func append(_ event: AgentActivityEvent) {
        appended.append(event)
    }
}
```

Adjust `makeAppState()` to accept and pass the fake:

```swift
private func makeAppState(activityLog: ActivityLogStoring = FakeActivityLogStore()) -> AppState {
    AppState(
        selectionStore: AgentActivitySelectionStoreStub(),
        terminalViews: AgentActivityTerminalViewRemovingStub(),
        workspacePersistence: AgentActivityWorkspacePersistenceStub(),
        activityLog: activityLog
    )
}
```

Add new tests:

```swift
@Test("logs an event when transitioning running to awaiting")
func logsRunningToAwaiting() {
    let log = FakeActivityLogStore()
    let appState = makeAppState(activityLog: log)
    let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
    let area = TabArea(projectPath: "/tmp/wt")
    area.createAgentTab(kind: .codex)
    let pane = area.activeTab!.content.pane!
    pane.activityState = .running
    appState.workspaceRoots[key] = .tabArea(area)

    let updated = appState.updateAgentActivity(paneID: pane.id, state: .awaiting)

    #expect(updated == true)
    #expect(log.appended.count == 1)
    #expect(log.appended.first?.paneID == pane.id)
    #expect(log.appended.first?.from == .running)
    #expect(log.appended.first?.to == .awaiting)
}

@Test("does not log when activity state is unchanged")
func doesNotLogWhenUnchanged() {
    let log = FakeActivityLogStore()
    let appState = makeAppState(activityLog: log)
    let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
    let area = TabArea(projectPath: "/tmp/wt")
    area.createAgentTab(kind: .codex)
    let pane = area.activeTab!.content.pane!
    pane.activityState = .running
    appState.workspaceRoots[key] = .tabArea(area)

    appState.updateAgentActivity(paneID: pane.id, state: .running)

    #expect(log.appended.isEmpty)
}

@Test("does not log when transition is suppressed by the state machine")
func doesNotLogSuppressedTransition() {
    let log = FakeActivityLogStore()
    let appState = makeAppState(activityLog: log)
    let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
    let area = TabArea(projectPath: "/tmp/wt")
    area.createAgentTab(kind: .codex)
    let pane = area.activeTab!.content.pane!
    pane.activityState = .completed
    appState.workspaceRoots[key] = .tabArea(area)

    appState.updateAgentActivity(paneID: pane.id, state: .awaiting)

    #expect(pane.activityState == .completed)
    #expect(log.appended.isEmpty)
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `swift test --filter RoostTests.AppStateAgentActivityTests`
Expected: FAIL — `AppState.init` does not yet accept `activityLog:`.

- [ ] **Step 3: Add `activityLog` to `AppState`**

In `Muxy/Models/AppState.swift`:

1. Add a stored property near the other dependencies:

```swift
private let activityLog: ActivityLogStoring
```

2. Add `activityLog: ActivityLogStoring` to the designated initializer's parameter list and assign it. The new init signature:

```swift
init(
    selectionStore: any ActiveProjectSelectionStoring,
    terminalViews: any TerminalViewRemoving,
    workspacePersistence: any WorkspacePersisting,
    hostdRuntimeOwnership: HostdRuntimeOwnership = .appOwnedMetadataOnly,
    appConfigProvider: @escaping () -> RoostConfig? = { nil },
    projectConfigProvider: @escaping (String) -> RoostConfig? = RoostConfigLoader.load(fromProjectPath:),
    activityLog: ActivityLogStoring
) {
    self.selectionStore = selectionStore
    self.terminalViews = terminalViews
    self.workspacePersistence = workspacePersistence
    self.hostdRuntimeOwnership = hostdRuntimeOwnership
    self.appConfigProvider = appConfigProvider
    self.projectConfigProvider = projectConfigProvider
    self.activityLog = activityLog
}
```

3. Rewrite `updateAgentActivity` so the outer loop captures the `(key, root)` pair and the appended event reuses `key.projectID` / `key.worktreeID` without re-walking `workspaceRoots`:

```swift
@discardableResult
func updateAgentActivity(paneID: UUID, state: AgentActivityState) -> Bool {
    for (key, root) in workspaceRoots {
        for area in root.allAreas() {
            for tab in area.tabs {
                guard let pane = tab.content.pane, pane.id == paneID else { continue }
                guard pane.activityState != state else { return true }
                if state == .completed,
                   pane.activityState == .awaiting || pane.activityState == .exited
                {
                    return true
                }
                if state == .awaiting,
                   pane.activityState == .exited
                {
                    return true
                }
                let previous = pane.activityState
                if state == .awaiting {
                    pane.previousActivityState = pane.activityState
                }
                pane.activityState = state
                advanceAgentActivityRevision()
                activityLog.append(AgentActivityEvent(
                    paneID: pane.id,
                    projectID: key.projectID,
                    worktreeID: key.worktreeID,
                    from: previous,
                    to: state
                ))
                return true
            }
        }
    }
    return false
}
```

Note: if Phase A's version of `updateAgentActivity` already used `for root in workspaceRoots.values`, switch it to `for (key, root) in workspaceRoots` here. Do not add separate `projectID(for:)` / `worktreeID(for:)` helpers — they would re-traverse the whole tree on every transition.

- [ ] **Step 4: Run all tests**

Run: `swift test`
Expected: PASS — including the new transition-logging tests.

- [ ] **Step 5: Wire production `AppState` to a live `ActivityLogStore`**

The production construction site is `Muxy/MuxyApp.swift:27-33`. Edit that block to add the `activityLog` argument:

```swift
let appState = AppState(
    selectionStore: environment.selectionStore,
    terminalViews: environment.terminalViews,
    workspacePersistence: environment.workspacePersistence,
    hostdRuntimeOwnership: hostdRuntimeOwnership,
    appConfigProvider: { try? RoostAppConfigStore.load() },
    activityLog: ActivityLogStore()
)
```

Confirm there are no other `AppState(` call sites in `Muxy/` (tests use the helper from `AppStateAgentActivityTests.swift` updated in Step 2):

```
rg -n "AppState\(" Muxy/
```

Expected: only the line above is affected outside tests.

- [ ] **Step 6: Run lint**

Run: `scripts/checks.sh`
Expected: PASS.

- [ ] **Step 7: Manual end-to-end verification**

Run: `swift run Roost`. With an agent pane focused, send a Claude prompt and let it complete. Then:

```bash
cat ~/Library/Application\ Support/Roost/activity-log.json | jq '.[-5:]'
```

Expected: a JSON array with the last events for the pane, including a `running` → `completed` transition with a `paneID` matching the focused pane. This works regardless of whether the same hook produced a notification.

- [ ] **Step 8: Commit**

```bash
jj commit -m "feat(activity): persist agent activity transitions to activity-log.json"
```

---

## Self-Review Checklist

- [ ] Spec coverage: rename (A1, A2), color flip (A3), unsuppressed `completed → awaiting` transition (A2 Step 2 + Step 8), log on transition (B3 Step 3), focus-independent persistence (B2 + B3) — each requirement maps to a task above.
- [ ] No placeholders: every step contains the code or command needed.
- [ ] Type consistency: `AgentActivityState.awaiting`, `AgentActivityEvent`, `ActivityLogStoring`, `ActivityLogStore` are referenced consistently across tasks.
- [ ] No `.needsInput` literal remains anywhere after Task A2 Step 8.
- [ ] No new git commands; commits use `jj commit -m`.
