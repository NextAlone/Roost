# Phase 6c + 6d — Hostd Client Abstraction + Session History UI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Introduce a `RoostHostdClient` Swift-protocol abstraction so call sites are XPC-ready (Phase 6c). Add session history sidebar UI + stale-session cleanup on launch + re-launch button (Phase 6d).

**Architecture:** `RoostHostdClient` is a Swift protocol with async methods matching today's `RoostHostd` actor surface. `LocalHostdClient` wraps the actor and is the current implementation. A future `XPCHostdClient` will wrap an `NSXPCConnection.remoteObjectProxy` — that work is pure infrastructure (NSSecureCoding marshalling + bundle setup) and lives outside this plan. SwiftUI environment changes from `\.roostHostd` to `\.roostHostdClient`. `SessionHistoryStore` (@Observable @MainActor) reads via the client; `SessionHistoryView` renders a list with re-launch buttons.

**Tech Stack:** Swift 6, SwiftUI, swift-testing.

**Locked decisions:**
- `RoostHostdClient` is a Swift `protocol` (NOT `@objc`) — async methods returning `[SessionRecord]`. NSXPC marshalling concerns live in the future `XPCHostdClient`, not in this protocol's shape.
- Stale-session cleanup runs on `MuxyApp` launch via the client: any record with `lastState == .running` gets flipped to `.exited`. Reasoning: in-process hostd implies process death == all sessions dead. When real XPC arrives, this cleanup will be skipped or scoped differently.
- "Re-launch" opens a new agent tab using the original `(projectID, worktreeID, agentKind)`. If the project or worktree no longer exists, the entry shows but the button is disabled.
- Session history view lives as a sheet accessible via a sidebar gear/menu — not as a permanent sidebar section (avoids cluttering the existing project list).
- History view shows the most recent 50 sessions sorted by `createdAt DESC`. Older entries are still in the DB (no auto-prune); user can run `pruneExited` via a dedicated button.

**Out of scope:**
- Real XPC service bundle / .xcodeproj surgery (separate future task).
- Cross-process PTY ownership.
- Live session attach (impossible without process boundary).
- Search / filter in history.

---

## File Structure

**Create:**
- `Muxy/Services/Hostd/RoostHostdClient.swift` — protocol + LocalHostdClient + EnvironmentKey
- `Muxy/Services/Hostd/SessionHistoryStore.swift` — @Observable @MainActor wrapper
- `Muxy/Views/Hostd/SessionHistoryView.swift` — SwiftUI history sheet
- `Tests/MuxyTests/Hostd/RoostHostdClientTests.swift`
- `Tests/MuxyTests/Hostd/SessionHistoryStoreTests.swift`

**Modify:**
- `Muxy/Services/Hostd/RoostHostd.swift` — add `markAllRunningExited()` method; remove (or keep for backwards-compat) the old EnvironmentKey
- `Muxy/Models/AppState.swift` — `createAgentTab(_:projectID:hostd:)` → `createAgentTab(_:projectID:hostdClient:)`
- `Muxy/Services/ShortcutActionDispatcher.swift` — `hostd:` → `hostdClient:`
- `Muxy/Commands/MuxyCommands.swift` — `hostd:` → `hostdClient:`
- `Muxy/Views/Workspace/TabAreaView.swift` — read `\.roostHostdClient` instead of `\.roostHostd`
- `Muxy/MuxyApp.swift` — `@State hostdClient: (any RoostHostdClient)?`; `.task` initializes via `LocalHostdClient`; calls `markAllRunningExited()` on launch
- `Muxy/Views/Sidebar.swift` (or wherever sidebar is rendered) — add a button/menu entry to open the history sheet

---

## Task 1: RoostHostdClient protocol + LocalHostdClient

**Files:**
- Create: `Muxy/Services/Hostd/RoostHostdClient.swift`
- Test: `Tests/MuxyTests/Hostd/RoostHostdClientTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("LocalHostdClient")
struct RoostHostdClientTests {
    private func makeTempStoreURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-tests")
            .appendingPathComponent(UUID().uuidString)
        return tmp.appendingPathComponent("sessions.sqlite")
    }

    @Test("create + listLive round-trip via client")
    func createAndList() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let hostd = try await RoostHostd(databaseURL: url)
        let client: any RoostHostdClient = LocalHostdClient(hostd: hostd)

        let id = UUID()
        try await client.createSession(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .claudeCode,
            command: "claude"
        )
        let live = try await client.listLiveSessions()
        #expect(live.count == 1)
        #expect(live.first?.id == id)
    }

    @Test("markExited via client flips record state")
    func markExited() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let hostd = try await RoostHostd(databaseURL: url)
        let client: any RoostHostdClient = LocalHostdClient(hostd: hostd)

        let id = UUID()
        try await client.createSession(id: id, projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/wt", agentKind: .codex, command: "codex")
        try await client.markExited(sessionID: id)
        let all = try await client.listAllSessions()
        #expect(all.first?.lastState == .exited)
    }
}
```

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter RoostHostdClientTests
```

- [ ] **Step 3: Implement**

Create `Muxy/Services/Hostd/RoostHostdClient.swift`:

```swift
import Foundation
import MuxyShared
import SwiftUI

protocol RoostHostdClient: Sendable {
    func createSession(
        id: UUID,
        projectID: UUID,
        worktreeID: UUID,
        workspacePath: String,
        agentKind: AgentKind,
        command: String?
    ) async throws

    func markExited(sessionID: UUID) async throws
    func listLiveSessions() async throws -> [SessionRecord]
    func listAllSessions() async throws -> [SessionRecord]
    func deleteSession(id: UUID) async throws
    func pruneExited() async throws
    func markAllRunningExited() async throws
}

struct LocalHostdClient: RoostHostdClient {
    private let hostd: RoostHostd

    init(hostd: RoostHostd) {
        self.hostd = hostd
    }

    func createSession(
        id: UUID,
        projectID: UUID,
        worktreeID: UUID,
        workspacePath: String,
        agentKind: AgentKind,
        command: String?
    ) async throws {
        try await hostd.createSession(
            id: id,
            projectID: projectID,
            worktreeID: worktreeID,
            workspacePath: workspacePath,
            agentKind: agentKind,
            command: command
        )
    }

    func markExited(sessionID: UUID) async throws {
        try await hostd.markExited(sessionID: sessionID)
    }

    func listLiveSessions() async throws -> [SessionRecord] {
        try await hostd.listLiveSessions()
    }

    func listAllSessions() async throws -> [SessionRecord] {
        try await hostd.listAllSessions()
    }

    func deleteSession(id: UUID) async throws {
        try await hostd.deleteSession(id: id)
    }

    func pruneExited() async throws {
        try await hostd.pruneExited()
    }

    func markAllRunningExited() async throws {
        try await hostd.markAllRunningExited()
    }
}

extension EnvironmentValues {
    @Entry var roostHostdClient: (any RoostHostdClient)? = nil
}
```

The `@Entry` macro is the Swift 6 SwiftUI form for declaring environment values (used in Phase 4b too).

- [ ] **Step 4: Add markAllRunningExited to RoostHostd actor**

In `Muxy/Services/Hostd/RoostHostd.swift`, add a new method:

```swift
    func markAllRunningExited() async throws {
        let live = try await store.list().filter { $0.lastState == .running }
        for record in live {
            try await store.update(id: record.id, lastState: .exited)
        }
    }
```

- [ ] **Step 5: Run targeted + full**

```bash
swift test --filter RoostHostdClientTests
swift test 2>&1 | tail -3
```

Expected: 2 new tests pass; total all green.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(hostd): RoostHostdClient protocol + LocalHostdClient implementation"
```

---

## Task 2: SessionHistoryStore

**Files:**
- Create: `Muxy/Services/Hostd/SessionHistoryStore.swift`
- Test: `Tests/MuxyTests/Hostd/SessionHistoryStoreTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("SessionHistoryStore")
struct SessionHistoryStoreTests {
    private actor StubClient: RoostHostdClient {
        var allSessions: [SessionRecord] = []
        var pruneCount: Int = 0

        nonisolated func createSession(id: UUID, projectID: UUID, worktreeID: UUID, workspacePath: String, agentKind: AgentKind, command: String?) async throws {}
        nonisolated func markExited(sessionID: UUID) async throws {}
        nonisolated func listLiveSessions() async throws -> [SessionRecord] { [] }
        nonisolated func deleteSession(id: UUID) async throws {}
        nonisolated func markAllRunningExited() async throws {}

        func listAllSessions() async throws -> [SessionRecord] { allSessions }
        func pruneExited() async throws { pruneCount += 1 }

        func setAllSessions(_ records: [SessionRecord]) { allSessions = records }
    }

    @Test("starts empty until refreshed")
    func startsEmpty() {
        let store = SessionHistoryStore()
        #expect(store.records.isEmpty)
    }

    @Test("refresh populates records via client")
    func refreshPopulates() async throws {
        let stub = StubClient()
        let record = SessionRecord(id: UUID(), projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/wt", agentKind: .claudeCode, command: "claude", createdAt: Date(), lastState: .exited)
        await stub.setAllSessions([record])
        let store = SessionHistoryStore(client: stub)
        await store.refresh()
        #expect(store.records.count == 1)
        #expect(store.records.first?.agentKind == .claudeCode)
    }
}
```

The stub uses `nonisolated` for protocol methods we don't care about, returning empty / no-op. Only the methods we actually exercise are isolated to the actor's storage.

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter SessionHistoryStoreTests
```

- [ ] **Step 3: Implement**

Create `Muxy/Services/Hostd/SessionHistoryStore.swift`:

```swift
import Foundation
import MuxyShared
import Observation

@MainActor
@Observable
final class SessionHistoryStore {
    private(set) var records: [SessionRecord] = []
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    private let client: (any RoostHostdClient)?

    init(client: (any RoostHostdClient)? = nil) {
        self.client = client
    }

    func refresh() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await client.listAllSessions()
            records = result
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func prune() async {
        guard let client else { return }
        do {
            try await client.pruneExited()
            await refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
```

- [ ] **Step 4: Run targeted + full**

```bash
swift test --filter SessionHistoryStoreTests
swift test 2>&1 | tail -3
```

Expected: 2 tests pass; total all green.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(hostd): SessionHistoryStore observable wrapper"
```

---

## Task 3: Migrate environment + call sites from RoostHostd to RoostHostdClient

**Files:**
- Modify: `Muxy/MuxyApp.swift`
- Modify: `Muxy/Models/AppState.swift`
- Modify: `Muxy/Services/ShortcutActionDispatcher.swift`
- Modify: `Muxy/Commands/MuxyCommands.swift`
- Modify: `Muxy/Views/Workspace/TabAreaView.swift`

The old `\.roostHostd` Environment key is replaced by `\.roostHostdClient`.

- [ ] **Step 1: MuxyApp**

In `Muxy/MuxyApp.swift`:

Replace:
```swift
    @State private var hostd: RoostHostd?
```
with:
```swift
    @State private var hostdClient: (any RoostHostdClient)?
```

Replace the existing `.task { ... }` block:
```swift
                .task {
                    if hostd == nil {
                        hostd = try? await RoostHostd()
                    }
                }
```
with:
```swift
                .task {
                    if hostdClient == nil {
                        if let hostd = try? await RoostHostd() {
                            try? await hostd.markAllRunningExited()
                            hostdClient = LocalHostdClient(hostd: hostd)
                        }
                    }
                }
```

Replace `.environment(\.roostHostd, hostd)` with `.environment(\.roostHostdClient, hostdClient)` in BOTH the WindowGroup body and the VCS Window body.

For `MuxyCommands(...)` constructor: replace `hostd: hostd` with `hostdClient: hostdClient`.

- [ ] **Step 2: AppState**

In `Muxy/Models/AppState.swift`, find `func createAgentTab(_ kind: AgentKind, projectID: UUID, hostd: RoostHostd? = nil)`. Replace:

```swift
    func createAgentTab(_ kind: AgentKind, projectID: UUID, hostdClient: (any RoostHostdClient)? = nil) {
        dispatch(.createAgentTab(projectID: projectID, areaID: nil, kind: kind))
        guard let hostdClient,
              let area = focusedArea(for: projectID),
              let tab = area.activeTab,
              let pane = tab.content.pane,
              let worktreeID = activeWorktreeID[projectID]
        else { return }
        let paneID = pane.id
        let workspacePath = pane.projectPath
        let agentKind = pane.agentKind
        let command = pane.startupCommand
        Task { [hostdClient] in
            try? await hostdClient.createSession(
                id: paneID,
                projectID: projectID,
                worktreeID: worktreeID,
                workspacePath: workspacePath,
                agentKind: agentKind,
                command: command
            )
        }
    }
```

- [ ] **Step 3: ShortcutActionDispatcher**

In `Muxy/Services/ShortcutActionDispatcher.swift`, replace the `hostd: RoostHostd?` field/init param with `hostdClient: (any RoostHostdClient)?`. In `performAgentTab`, replace `hostd: hostd` with `hostdClient: hostdClient`.

- [ ] **Step 4: MuxyCommands**

In `Muxy/Commands/MuxyCommands.swift`, replace `let hostd: RoostHostd?` with `let hostdClient: (any RoostHostdClient)?`. In `shortcutDispatcher`, replace `hostd: hostd` with `hostdClient: hostdClient`.

- [ ] **Step 5: TabAreaView**

In `Muxy/Views/Workspace/TabAreaView.swift`, replace:
```swift
    @Environment(\.roostHostd) private var hostd
```
with:
```swift
    @Environment(\.roostHostdClient) private var hostdClient
```

In the `onProcessExit:` closure, replace `if let hostd { Task { [hostd] in try? await hostd.markExited(...) } }` with `if let hostdClient { Task { [hostdClient] in try? await hostdClient.markExited(...) } }`.

- [ ] **Step 6: Remove old RoostHostd EnvironmentKey extension**

Find and delete the existing `extension EnvironmentValues { @Entry var roostHostd: RoostHostd? = nil }` declaration in `Muxy/Services/Hostd/RoostHostd.swift`. The new key (in `RoostHostdClient.swift`) replaces it.

- [ ] **Step 7: Build + test**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -3
```

Expected SUCCESS, all green.

- [ ] **Step 8: Commit**

```bash
jj commit -m "refactor(hostd): migrate call sites to RoostHostdClient + stale cleanup on launch"
```

---

## Task 4: SessionHistoryView

**Files:**
- Create: `Muxy/Views/Hostd/SessionHistoryView.swift`

- [ ] **Step 1: Implement**

Create `Muxy/Views/Hostd/SessionHistoryView.swift`:

```swift
import MuxyShared
import SwiftUI

struct SessionHistoryView: View {
    let onRelaunch: (SessionRecord) -> Void
    let onClose: () -> Void

    @Environment(\.roostHostdClient) private var hostdClient
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var store = SessionHistoryStore()

    private let limit = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(width: 560, height: 480)
        .task {
            store = SessionHistoryStore(client: hostdClient)
            await store.refresh()
        }
    }

    private var header: some View {
        HStack {
            Text("Session History")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading)
            .accessibilityLabel("Refresh")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.errorMessage {
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.diffRemoveFg)
        } else if store.isLoading, store.records.isEmpty {
            ProgressView().controlSize(.small)
        } else if store.records.isEmpty {
            Text("No sessions yet")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgDim)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.records.prefix(limit), id: \.id) { record in
                        row(record: record)
                    }
                }
            }
        }
    }

    private func row(record: SessionRecord) -> some View {
        HStack(spacing: 6) {
            Image(systemName: record.agentKind.iconSystemName)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgDim)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.agentKind.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                Text(record.workspacePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(stateLabel(record.lastState))
                .font(.system(size: 10))
                .foregroundStyle(stateColor(record.lastState))
            Button("Re-launch") {
                onRelaunch(record)
            }
            .buttonStyle(.borderless)
            .disabled(!canRelaunch(record))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    private func stateLabel(_ state: SessionLifecycleState) -> String {
        switch state {
        case .running: "running"
        case .exited: "exited"
        }
    }

    private func stateColor(_ state: SessionLifecycleState) -> Color {
        switch state {
        case .running: MuxyTheme.diffAddFg
        case .exited: MuxyTheme.fgDim
        }
    }

    private func canRelaunch(_ record: SessionRecord) -> Bool {
        guard projectStore.projects.contains(where: { $0.id == record.projectID }) else { return false }
        let worktrees = worktreeStore.worktrees[record.projectID] ?? []
        return worktrees.contains(where: { $0.id == record.worktreeID })
    }

    private var footer: some View {
        HStack {
            Button("Prune Exited") {
                Task { await store.prune() }
            }
            .disabled(store.isLoading)
            Spacer()
            Button("Close") { onClose() }
                .keyboardShortcut(.cancelAction)
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
jj commit -m "feat(hostd): SessionHistoryView lists past sessions with re-launch"
```

---

## Task 5: Wire history sheet into the sidebar / commands

**Files:**
- Modify: `Muxy/Views/Sidebar.swift` (or wherever sidebar headers live — grep first)

The history view needs an entry point. Add a button in the sidebar header (or under a gear menu) that opens the sheet.

- [ ] **Step 1: Find a sidebar header**

```bash
grep -n "struct Sidebar\|toolbarItem\|@State.*showSettings\|sidebarExpanded" Muxy/Views/Sidebar.swift Muxy/Views/MainWindow.swift 2>/dev/null | head -10
```

Pick a sensible location. The simplest: add a small button in `Sidebar.swift` near the top of the sidebar's container that opens a sheet.

- [ ] **Step 2: Add state + sheet**

In `Sidebar.swift` (or wherever), add `@State private var showSessionHistory = false` and a button (e.g., next to existing sidebar header buttons):

```swift
    Button {
        showSessionHistory = true
    } label: {
        Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: 11))
    }
    .buttonStyle(.borderless)
    .help("Session History")
```

Then attach a `.sheet(isPresented: $showSessionHistory)` modifier on a parent view:

```swift
    .sheet(isPresented: $showSessionHistory) {
        SessionHistoryView(
            onRelaunch: { record in
                showSessionHistory = false
                relaunch(record: record)
            },
            onClose: { showSessionHistory = false }
        )
    }
```

Add a helper `relaunch(record:)` that:

```swift
    private func relaunch(record: SessionRecord) {
        guard let project = projectStore.projects.first(where: { $0.id == record.projectID }) else { return }
        let worktrees = worktreeStore.worktrees[record.projectID] ?? []
        guard let worktree = worktrees.first(where: { $0.id == record.worktreeID }) else { return }
        appState.selectProject(project, worktree: worktree)
        appState.createAgentTab(record.agentKind, projectID: project.id, hostdClient: hostdClient)
    }
```

This requires `@Environment(AppState.self)`, `@Environment(ProjectStore.self)`, `@Environment(WorktreeStore.self)`, and `@Environment(\.roostHostdClient) private var hostdClient` declarations on the view that owns the sheet. Add those if missing.

If the sidebar's outer view doesn't have these environments, add the button + sheet at the level that does (perhaps `MainWindow.swift` instead).

- [ ] **Step 3: Build + manual smoke**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -3
```

Expected SUCCESS, all green.

Manual smoke (after `swift run Muxy`):
- Open a project, create a Claude Code agent tab.
- Quit Claude (`/exit`) — pane should remain visible with `.exited` badge.
- Click the new history button — sheet shows the recent session as `exited`.
- Click "Re-launch" — a new Claude Code tab opens in the same workspace.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(sidebar): session history sheet entry point + re-launch wiring"
```

---

## Task 6: Migration plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append after Phase 6a+6b status block**

```markdown
**Status (2026-04-28): Phase 6c + 6d (client abstraction + history UI) landed.**

- `RoostHostdClient` Swift protocol decouples call sites from the in-process actor. `LocalHostdClient` is the current implementation; future `XPCHostdClient` will wrap `NSXPCConnection` once an XPC service bundle is built (separate task — needs Xcode project surgery).
- All call sites (AppState.createAgentTab, ShortcutActionDispatcher, MuxyCommands, TabAreaView) now go through `(any RoostHostdClient)?` rather than the raw actor.
- On launch, `RoostHostd.markAllRunningExited()` flips any leftover `.running` records to `.exited` (in-process hostd implies process death == sessions dead). Real XPC will skip this.
- `SessionHistoryStore` (@Observable @MainActor) wraps client.listAllSessions; `SessionHistoryView` renders the recent 50 sessions with state badge + Re-launch + Prune Exited buttons.
- Re-launch opens a new agent tab in the same project + worktree (best-effort). Disabled if project / worktree no longer exists.
- Sidebar gains a clock-arrow button that opens the history sheet.
- **Phase 6 in-process work complete.** Real cross-process XPC service is queued as a separate infrastructure task (Xcode project + xcodebuild + codesign work).
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(plan): mark Phase 6c + 6d (client + history) landed; in-process Phase 6 complete"
```

---

## Self-Review Checklist

- [ ] All call sites use `RoostHostdClient`, not `RoostHostd` actor directly.
- [ ] `\.roostHostd` Environment key is gone; only `\.roostHostdClient` remains.
- [ ] Stale-session cleanup on launch is wired in `MuxyApp`.
- [ ] History view "Re-launch" button respects project/worktree existence.
- [ ] No comments added.
- [ ] Build + test green.
