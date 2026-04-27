# Phase 4b — Workspace Status Watcher + Badges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Add reactive workspace status badges (clean / dirty / conflicted) in the sidebar, fed by a fs-watcher that observes jj op_heads / git HEAD changes and re-runs `jj status` / `git status --porcelain` at-op.

**Architecture:** Introduce `WorkspaceStatus` enum in MuxyShared, extend `VcsStatusProbe` protocol with a `status(at:)` method, build a `WorkspaceStatusStore` (@Observable @MainActor) that owns per-worktree `WorkspaceStatusWatcher` instances and stores `[UUID: WorkspaceStatus]`. Sidebar rows render a colored dot via a small `WorkspaceStatusBadge` view. Watcher is purpose-built — separate from the existing `VcsDirectoryWatcher` (which serves diff refresh and intentionally ignores `.jj/`). Reconciliation hooks into `WorktreeStore` via `.onChange` in the root view.

**Tech Stack:** Swift 6, SwiftUI, swift-testing, FSEventStream (CoreServices), existing `JjStatusParser`, `JjProcessRunner`.

**Locked decisions:**
- Status states: `clean`, `dirty`, `conflicted`, `unknown`. `unknown` = haven't probed yet or probe failed; render as no badge (or muted dot).
- Watcher = new class; the existing `VcsDirectoryWatcher` stays unchanged (different consumer / different filter rules).
- Watcher signal sources:
  - **jj**: watch entire `<repo>/.jj/` directory; debounce 0.3s; on any event, re-query (no noise filter — we WANT op_heads / op_log changes to fire)
  - **git**: watch `<repo>/.git/HEAD`, `<repo>/.git/index`, plus working-copy file changes; same debounce
- Probe semantics:
  - **jj**: `jj status --ignore-working-copy` (avoids triggering an implicit snapshot, per Phase 1 policy). Parse with existing `JjStatusParser`. Conflicts win over dirty.
  - **git**: `git status --porcelain=v1`. If any line starts with `UU`, `AA`, `DD` (unmerged), → `conflicted`. Else if any line, → `dirty`. Else → `clean`.
- Lifecycle: `WorkspaceStatusStore.reconcile(worktrees:)` is called whenever `WorktreeStore.worktrees` changes, plus once on launch. Reconciliation = start new, stop removed (`worktree.id` is stable).
- Status update is async; UI shows previous value (or `.unknown`) until probe completes — no spinner needed for Phase 4b.

**Out of scope:**
- "Running agent" badge (covered in Phase 4c when sessions land).
- Polling fallback if FSEventStream fails.
- Bookmark-list / change-id hovers (Phase 5).
- Refactoring `VcsDirectoryWatcher` for shared infrastructure.
- Migrating Remove flow's `hasUncommittedChanges` to use new `status` method (keep old method too — no breaking change).

---

## File Structure

**Create:**
- `MuxyShared/Vcs/WorkspaceStatus.swift` — enum + Codable (Codable in case persistence is added later)
- `Muxy/Services/Vcs/WorkspaceStatusWatcher.swift` — FSEventStream wrapper purpose-built for status changes
- `Muxy/Services/WorkspaceStatusStore.swift` — `@Observable @MainActor final class`
- `Tests/MuxyTests/Vcs/WorkspaceStatusTests.swift`
- `Tests/MuxyTests/Services/WorkspaceStatusStoreTests.swift`
- `Muxy/Views/Sidebar/WorkspaceStatusBadge.swift` — small SwiftUI view

**Modify:**
- `Muxy/Services/Vcs/VcsStatusProbe.swift` — add `status(at:)` method to protocol; default impl maps existing `hasUncommittedChanges` → `dirty | clean` for backwards compat
- `Muxy/Services/Vcs/JjStatusProbe.swift` — implement `status(at:)` using existing parser
- `Muxy/Services/Vcs/GitStatusProbe.swift` — implement `status(at:)` parsing porcelain
- `Muxy/Views/Sidebar/ExpandedProjectRow.swift` — render badge in worktree row
- `Muxy/Views/Sidebar/WorktreePopover.swift` — render badge in worktree row
- (Root view, e.g. `Muxy/Views/MuxyRootView.swift` or `Muxy/MuxyApp.swift`) — `.onChange(of: worktreeStore.worktrees)` → `statusStore.reconcile(...)`

---

## Task 1: WorkspaceStatus enum

**Files:**
- Create: `MuxyShared/Vcs/WorkspaceStatus.swift`
- Test: `Tests/MuxyTests/Vcs/WorkspaceStatusTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import MuxyShared
import Testing

@Suite("WorkspaceStatus")
struct WorkspaceStatusTests {
    @Test("Codable round-trips all cases")
    func codableRoundTrip() throws {
        let original = WorkspaceStatus.allCases
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([WorkspaceStatus].self, from: data)
        #expect(decoded == original)
    }

    @Test("raw values are stable")
    func rawValuesStable() {
        #expect(WorkspaceStatus.clean.rawValue == "clean")
        #expect(WorkspaceStatus.dirty.rawValue == "dirty")
        #expect(WorkspaceStatus.conflicted.rawValue == "conflicted")
        #expect(WorkspaceStatus.unknown.rawValue == "unknown")
    }

    @Test("conflicted dominates dirty in merge")
    func conflictedDominates() {
        #expect(WorkspaceStatus.conflicted.dominates(.dirty))
        #expect(WorkspaceStatus.conflicted.dominates(.clean))
        #expect(WorkspaceStatus.dirty.dominates(.clean))
        #expect(!WorkspaceStatus.clean.dominates(.dirty))
    }
}
```

- [ ] **Step 2: Run test, expect failure**

```bash
swift test --filter WorkspaceStatusTests
```

- [ ] **Step 3: Implement**

Create `MuxyShared/Vcs/WorkspaceStatus.swift`:

```swift
import Foundation

public enum WorkspaceStatus: String, Sendable, Codable, Hashable, CaseIterable {
    case clean
    case dirty
    case conflicted
    case unknown

    public func dominates(_ other: WorkspaceStatus) -> Bool {
        rank > other.rank
    }

    private var rank: Int {
        switch self {
        case .unknown: 0
        case .clean: 1
        case .dirty: 2
        case .conflicted: 3
        }
    }
}
```

- [ ] **Step 4: Run test, expect 3 pass**

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(vcs): add WorkspaceStatus enum"
```

---

## Task 2: Extend VcsStatusProbe protocol with status(at:)

**Files:**
- Modify: `Muxy/Services/Vcs/VcsStatusProbe.swift`

The existing protocol has `hasUncommittedChanges(at:)`. Add a new method `status(at:) -> WorkspaceStatus` with a default implementation that maps the existing bool to `dirty/clean`. This way no concrete probe is forced to implement both at once; we'll override in Tasks 3 and 4 for richer semantics.

- [ ] **Step 1: Read the file**

```bash
cat Muxy/Services/Vcs/VcsStatusProbe.swift
```

- [ ] **Step 2: Replace the protocol declaration**

Find:

```swift
protocol VcsStatusProbe: Sendable {
    func hasUncommittedChanges(at worktreePath: String) async -> Bool
}
```

Replace with:

```swift
protocol VcsStatusProbe: Sendable {
    func hasUncommittedChanges(at worktreePath: String) async -> Bool
    func status(at worktreePath: String) async -> WorkspaceStatus
}

extension VcsStatusProbe {
    func status(at worktreePath: String) async -> WorkspaceStatus {
        await hasUncommittedChanges(at: worktreePath) ? .dirty : .clean
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```

Expected SUCCESS — concrete types still compile because they get the default `status(at:)`.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(vcs): VcsStatusProbe.status(at:) with bool-mapping default"
```

---

## Task 3: JjStatusProbe.status(at:) implementation

**Files:**
- Modify: `Muxy/Services/Vcs/JjStatusProbe.swift`
- Test: extend `Tests/MuxyTests/Services/Vcs/JjStatusProbeTests.swift` (create if absent)

- [ ] **Step 1: Find existing test file**

```bash
find Tests -name "*JjStatusProbe*" -type f
```

If a file exists, append tests there. Otherwise create `Tests/MuxyTests/Services/Vcs/JjStatusProbeTests.swift`.

- [ ] **Step 2: Add a test using closure injection**

Append (or create) with these tests:

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("JjStatusProbe.status")
struct JjStatusProbeStatusTests {
    @Test("clean when entries empty and no conflicts")
    func cleanCase() async {
        let probe = JjStatusProbe(statusJson: { _ in
            .success(entries: [], hasConflicts: false)
        })
        #expect(await probe.status(at: "/tmp/wt") == .clean)
    }

    @Test("dirty when entries non-empty")
    func dirtyCase() async {
        let probe = JjStatusProbe(statusJson: { _ in
            .success(entries: ["A path/to/file.swift"], hasConflicts: false)
        })
        #expect(await probe.status(at: "/tmp/wt") == .dirty)
    }

    @Test("conflicted dominates even with empty entries")
    func conflictedDominates() async {
        let probe = JjStatusProbe(statusJson: { _ in
            .success(entries: [], hasConflicts: true)
        })
        #expect(await probe.status(at: "/tmp/wt") == .conflicted)
    }

    @Test("failure → unknown")
    func failureCase() async {
        let probe = JjStatusProbe(statusJson: { _ in
            .failure
        })
        #expect(await probe.status(at: "/tmp/wt") == .unknown)
    }
}
```

The above test depends on a new init `JjStatusProbe(statusJson:)` that injects a closure. The closure returns a `JjStatusProbeRawResult` enum we will define as part of the implementation.

- [ ] **Step 3: Run test, expect failure**

```bash
swift test --filter JjStatusProbeStatusTests
```

- [ ] **Step 4: Implement**

Replace `Muxy/Services/Vcs/JjStatusProbe.swift` contents with:

```swift
import Foundation
import MuxyShared

enum JjStatusProbeRawResult: Sendable {
    case success(entries: [String], hasConflicts: Bool)
    case failure
}

struct JjStatusProbe: VcsStatusProbe {
    private let probe: @Sendable (String) async -> Bool
    private let statusProbe: @Sendable (String) async -> JjStatusProbeRawResult

    init(
        probe: @escaping @Sendable (String) async -> Bool = Self.defaultProbe,
        statusJson: @escaping @Sendable (String) async -> JjStatusProbeRawResult = Self.defaultStatusJson
    ) {
        self.probe = probe
        self.statusProbe = statusJson
    }

    func hasUncommittedChanges(at worktreePath: String) async -> Bool {
        await probe(worktreePath)
    }

    func status(at worktreePath: String) async -> WorkspaceStatus {
        switch await statusProbe(worktreePath) {
        case .failure:
            return .unknown
        case let .success(entries, hasConflicts):
            if hasConflicts { return .conflicted }
            return entries.isEmpty ? .clean : .dirty
        }
    }

    private static let defaultProbe: @Sendable (String) async -> Bool = { worktreePath in
        do {
            let result = try await JjProcessRunner.run(
                repoPath: worktreePath,
                command: ["status"],
                snapshot: .ignore
            )
            guard result.status == 0 else { return false }
            let raw = String(data: result.stdout, encoding: .utf8) ?? ""
            let status = try JjStatusParser.parse(raw)
            return !status.entries.isEmpty || status.hasConflicts
        } catch {
            return false
        }
    }

    private static let defaultStatusJson: @Sendable (String) async -> JjStatusProbeRawResult = { worktreePath in
        do {
            let result = try await JjProcessRunner.run(
                repoPath: worktreePath,
                command: ["status"],
                snapshot: .ignore
            )
            guard result.status == 0 else { return .failure }
            let raw = String(data: result.stdout, encoding: .utf8) ?? ""
            let status = try JjStatusParser.parse(raw)
            let entryStrings = status.entries.map(\.rawLine)
            return .success(entries: entryStrings, hasConflicts: status.hasConflicts)
        } catch {
            return .failure
        }
    }
}
```

If `JjStatusEntry` doesn't have a `rawLine` property, use any stable text representation — read `Muxy/Services/Jj/JjStatusParser.swift` first to see the actual struct.

- [ ] **Step 5: Run targeted + full suite**

```bash
swift test --filter JjStatusProbeStatusTests
swift test 2>&1 | tail -3
```

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(vcs): JjStatusProbe.status returns clean/dirty/conflicted"
```

---

## Task 4: GitStatusProbe.status(at:) implementation

**Files:**
- Modify: `Muxy/Services/Vcs/GitStatusProbe.swift`
- Test: extend or create `Tests/MuxyTests/Services/Vcs/GitStatusProbeTests.swift`

- [ ] **Step 1: Survey existing GitStatusProbe**

```bash
cat Muxy/Services/Vcs/GitStatusProbe.swift
find Tests -name "*GitStatusProbe*" -type f
```

If existing tests exist, add to that file. Otherwise create one.

- [ ] **Step 2: Add tests via closure injection**

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("GitStatusProbe.status")
struct GitStatusProbeStatusTests {
    @Test("empty porcelain → clean")
    func cleanCase() async {
        let probe = GitStatusProbe(porcelainJson: { _ in .success(lines: []) })
        #expect(await probe.status(at: "/tmp/wt") == .clean)
    }

    @Test("modified file → dirty")
    func dirtyCase() async {
        let probe = GitStatusProbe(porcelainJson: { _ in
            .success(lines: [" M README.md"])
        })
        #expect(await probe.status(at: "/tmp/wt") == .dirty)
    }

    @Test("UU line → conflicted")
    func conflictUU() async {
        let probe = GitStatusProbe(porcelainJson: { _ in
            .success(lines: ["UU README.md"])
        })
        #expect(await probe.status(at: "/tmp/wt") == .conflicted)
    }

    @Test("AA line → conflicted")
    func conflictAA() async {
        let probe = GitStatusProbe(porcelainJson: { _ in
            .success(lines: ["AA new-file"])
        })
        #expect(await probe.status(at: "/tmp/wt") == .conflicted)
    }

    @Test("conflict + dirty → conflicted")
    func conflictDominates() async {
        let probe = GitStatusProbe(porcelainJson: { _ in
            .success(lines: [" M README.md", "UU conflict.txt"])
        })
        #expect(await probe.status(at: "/tmp/wt") == .conflicted)
    }

    @Test("failure → unknown")
    func failureCase() async {
        let probe = GitStatusProbe(porcelainJson: { _ in .failure })
        #expect(await probe.status(at: "/tmp/wt") == .unknown)
    }
}
```

- [ ] **Step 3: Run test, expect failure**

```bash
swift test --filter GitStatusProbeStatusTests
```

- [ ] **Step 4: Implement**

The current `GitStatusProbe` delegates to `GitWorktreeService`. Add the new closure-injected status path. Replace `Muxy/Services/Vcs/GitStatusProbe.swift` with:

```swift
import Foundation
import MuxyShared

enum GitStatusProbeRawResult: Sendable {
    case success(lines: [String])
    case failure
}

struct GitStatusProbe: VcsStatusProbe {
    private let porcelain: @Sendable (String) async -> GitStatusProbeRawResult

    init(porcelainJson: @escaping @Sendable (String) async -> GitStatusProbeRawResult = Self.defaultPorcelain) {
        self.porcelain = porcelainJson
    }

    func hasUncommittedChanges(at worktreePath: String) async -> Bool {
        await GitWorktreeService.shared.hasUncommittedChanges(worktreePath: worktreePath)
    }

    func status(at worktreePath: String) async -> WorkspaceStatus {
        switch await porcelain(worktreePath) {
        case .failure:
            return .unknown
        case let .success(lines):
            let conflicted = lines.contains { line in
                guard line.count >= 2 else { return false }
                let prefix = String(line.prefix(2))
                return Self.conflictPrefixes.contains(prefix)
            }
            if conflicted { return .conflicted }
            return lines.isEmpty ? .clean : .dirty
        }
    }

    private static let conflictPrefixes: Set<String> = [
        "UU", "AA", "DD", "AU", "UA", "UD", "DU"
    ]

    private static let defaultPorcelain: @Sendable (String) async -> GitStatusProbeRawResult = { worktreePath in
        do {
            let lines = try await GitWorktreeService.shared.statusPorcelainLines(at: worktreePath)
            return .success(lines: lines)
        } catch {
            return .failure
        }
    }
}
```

If `GitWorktreeService` does not yet expose `statusPorcelainLines(at:)`, add the helper in that service (one-liner that runs `git status --porcelain=v1` and returns `[String]`).

- [ ] **Step 5: Run targeted + full suite**

```bash
swift test --filter GitStatusProbeStatusTests
swift test 2>&1 | tail -3
```

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(vcs): GitStatusProbe.status parses porcelain for conflicts"
```

---

## Task 5: WorkspaceStatusWatcher (FSEventStream wrapper)

**Files:**
- Create: `Muxy/Services/Vcs/WorkspaceStatusWatcher.swift`

This watcher is purpose-built for status reactivity. It does NOT filter `.jj/` events (unlike the existing `VcsDirectoryWatcher` which serves the diff panel and ignores `.jj/` noise). The handler fires once per debounced burst.

- [ ] **Step 1: Implement**

Create `Muxy/Services/Vcs/WorkspaceStatusWatcher.swift`:

```swift
import CoreServices
import Foundation
import MuxyShared

final class WorkspaceStatusWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.roost.workspace-status-watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var debounceWork: DispatchWorkItem?
    private let handler: @Sendable () -> Void

    init?(directoryPath: String, vcsKind: VcsKind, handler: @escaping @Sendable () -> Void) {
        let metaDir: String
        switch vcsKind {
        case .git: metaDir = ".git"
        case .jj: metaDir = ".jj"
        }
        let metaPath = (directoryPath as NSString).appendingPathComponent(metaDir)
        guard FileManager.default.fileExists(atPath: metaPath) else { return nil }

        self.handler = handler

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let paths = [directoryPath] as CFArray
        guard let stream = FSEventStreamCreate(
            nil,
            { _, clientInfo, numEvents, _, _, _ in
                guard let clientInfo, numEvents > 0 else { return }
                let watcher = Unmanaged<WorkspaceStatusWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
                watcher.scheduleRefresh()
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        debounceWork?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func scheduleRefresh() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.handler()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
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
jj commit -m "feat(vcs): add WorkspaceStatusWatcher (no jj noise filter)"
```

No tests for this task — FSEventStream is hard to unit test. Behavior is verified end-to-end via Task 6 store tests with manual trigger injection.

---

## Task 6: WorkspaceStatusStore

**Files:**
- Create: `Muxy/Services/WorkspaceStatusStore.swift`
- Test: `Tests/MuxyTests/Services/WorkspaceStatusStoreTests.swift`

- [ ] **Step 1: Write tests**

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("WorkspaceStatusStore")
struct WorkspaceStatusStoreTests {
    @Test("status defaults to .unknown for unknown id")
    func defaultUnknown() {
        let store = WorkspaceStatusStore()
        #expect(store.status(forWorktreeID: UUID()) == .unknown)
    }

    @Test("refresh sets status from probe")
    func refreshUsesProbe() async {
        let id = UUID()
        let probe = StubProbe(status: .conflicted)
        let store = WorkspaceStatusStore(probeFactory: { _ in probe })
        await store.refresh(worktreeID: id, path: "/tmp/wt", kind: .jj)
        #expect(store.status(forWorktreeID: id) == .conflicted)
    }

    @Test("reconcile drops removed worktrees")
    func reconcileDrops() async {
        let id = UUID()
        let probe = StubProbe(status: .dirty)
        let store = WorkspaceStatusStore(probeFactory: { _ in probe })
        await store.refresh(worktreeID: id, path: "/tmp/wt", kind: .jj)
        store.reconcile(activeIDs: [])
        #expect(store.status(forWorktreeID: id) == .unknown)
    }
}

private struct StubProbe: VcsStatusProbe {
    let status: WorkspaceStatus
    func hasUncommittedChanges(at worktreePath: String) async -> Bool {
        status == .dirty || status == .conflicted
    }
    func status(at worktreePath: String) async -> WorkspaceStatus { status }
}
```

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter WorkspaceStatusStoreTests
```

- [ ] **Step 3: Implement**

Create `Muxy/Services/WorkspaceStatusStore.swift`:

```swift
import Foundation
import MuxyShared
import Observation

@MainActor
@Observable
final class WorkspaceStatusStore {
    private(set) var statuses: [UUID: WorkspaceStatus] = [:]
    private var watchers: [UUID: WorkspaceStatusWatcher] = [:]
    private let probeFactory: @Sendable (VcsKind) -> any VcsStatusProbe

    init(probeFactory: @escaping @Sendable (VcsKind) -> any VcsStatusProbe = VcsStatusProbeFactory.probe(for:)) {
        self.probeFactory = probeFactory
    }

    func status(forWorktreeID id: UUID) -> WorkspaceStatus {
        statuses[id] ?? .unknown
    }

    func refresh(worktreeID id: UUID, path: String, kind: VcsKind) async {
        let probe = probeFactory(kind)
        let result = await probe.status(at: path)
        statuses[id] = result
    }

    func startWatching(worktreeID id: UUID, path: String, kind: VcsKind) {
        guard watchers[id] == nil else { return }
        let watcher = WorkspaceStatusWatcher(directoryPath: path, vcsKind: kind) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refresh(worktreeID: id, path: path, kind: kind)
            }
        }
        watchers[id] = watcher
        Task { await refresh(worktreeID: id, path: path, kind: kind) }
    }

    func stopWatching(worktreeID id: UUID) {
        watchers.removeValue(forKey: id)
        statuses.removeValue(forKey: id)
    }

    func reconcile(activeIDs: Set<UUID>) {
        let removed = Set(watchers.keys).subtracting(activeIDs)
        for id in removed {
            stopWatching(worktreeID: id)
        }
    }
}
```

- [ ] **Step 4: Run targeted + full suite**

```bash
swift test --filter WorkspaceStatusStoreTests
swift test 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(vcs): WorkspaceStatusStore tracks per-worktree status"
```

---

## Task 7: WorkspaceStatusBadge view + sidebar wiring

**Files:**
- Create: `Muxy/Views/Sidebar/WorkspaceStatusBadge.swift`
- Modify: `Muxy/Views/Sidebar/ExpandedProjectRow.swift`
- Modify: `Muxy/Views/Sidebar/WorktreePopover.swift`

- [ ] **Step 1: Create the badge view**

Create `Muxy/Views/Sidebar/WorkspaceStatusBadge.swift`:

```swift
import MuxyShared
import SwiftUI

struct WorkspaceStatusBadge: View {
    let status: WorkspaceStatus

    var body: some View {
        switch status {
        case .clean, .unknown:
            EmptyView()
        case .dirty:
            Circle()
                .fill(MuxyTheme.statusDirtyFg)
                .frame(width: 6, height: 6)
                .accessibilityLabel("Dirty")
        case .conflicted:
            Circle()
                .fill(MuxyTheme.diffRemoveFg)
                .frame(width: 6, height: 6)
                .accessibilityLabel("Conflicted")
        }
    }
}
```

If `MuxyTheme` doesn't have a `statusDirtyFg` color, reuse the existing `MuxyTheme.fgMuted` or `accent` color — pick a reasonable one and add a TODO via comment? **No** — the project rule is no comments. Pick a sensible existing color and proceed.

- [ ] **Step 2: Wire badge into `ExpandedProjectRow.swift`**

Find the worktree row rendering (search for `Text(worktree.name)` or similar). Inject:

```swift
@Environment(WorkspaceStatusStore.self) private var statusStore
```

at the top of any view that renders a worktree row. Add `WorkspaceStatusBadge(status: statusStore.status(forWorktreeID: worktree.id))` next to the worktree name (right after the name, before any badge currently displayed).

You will need to read the file to find the exact rendering locations — there may be 1-2 spots where a worktree name renders.

- [ ] **Step 3: Wire badge into `WorktreePopover.swift`**

Same pattern.

- [ ] **Step 4: Provide store via .environment in root view**

Find where `WorktreeStore` is provided (e.g., `Muxy/MuxyApp.swift` or `Muxy/Views/MuxyRootView.swift`). Right next to it, instantiate `WorkspaceStatusStore` and inject:

```swift
@State private var statusStore = WorkspaceStatusStore()
...
.environment(statusStore)
```

Then add an `.onChange(of: worktreeStore.worktrees)` handler at the same level:

```swift
.onChange(of: worktreeStore.worktrees, initial: true) { _, current in
    let activeIDs = Set(current.values.flatMap { $0.map(\.id) })
    statusStore.reconcile(activeIDs: activeIDs)
    for worktrees in current.values {
        for worktree in worktrees {
            statusStore.startWatching(
                worktreeID: worktree.id,
                path: worktree.path,
                kind: worktree.vcsKind
            )
        }
    }
}
```

The exact location of WorktreeStore injection determines where this goes. Read the root view file first.

- [ ] **Step 5: Build + test + manual smoke**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -3
```

Manual: `swift run Muxy`, open a project, modify a file in the working dir → sidebar dot should appear within ~0.6s. Revert the change → dot disappears.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(sidebar): render WorkspaceStatusBadge in workspace rows"
```

---

## Task 8: Migration plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append Phase 4b note**

Below the Phase 4a status block in the Phase 4 section, append:

```markdown
**Status (2026-04-28): Phase 4b (status watcher + badges) landed.**

- `WorkspaceStatus` enum (clean / dirty / conflicted / unknown) lives in `MuxyShared/Vcs/`.
- `VcsStatusProbe.status(at:)` extends the existing protocol; default implementation maps the legacy `hasUncommittedChanges` Bool to `.dirty`/`.clean`. Concrete probes override:
  - `JjStatusProbe.status` parses `jj status` (with `snapshot: .ignore`) for entries + `hasConflicts`. Conflicts dominate dirty.
  - `GitStatusProbe.status` parses `git status --porcelain=v1`; lines starting with `UU/AA/DD/AU/UA/UD/DU` mark conflicts.
- `WorkspaceStatusWatcher` is a new FSEventStream wrapper that does NOT filter `.jj/` events (purpose-built for status reactivity, separate from `VcsDirectoryWatcher` used by the diff panel).
- `WorkspaceStatusStore` (@Observable @MainActor) owns per-worktree watchers and `[UUID: WorkspaceStatus]`. Sidebar rows query via environment; `.onChange(of: worktreeStore.worktrees)` reconciles.
- Sidebar shows colored dot badges next to workspace names (no badge for `.clean`/`.unknown`).
- Phase 4c (session list under workspace) and Phase 4d (`requiresDedicatedWorkspace` enforcement) → upcoming.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(plan): mark Phase 4b (status watcher + badges) landed"
```

---

## Self-Review Checklist

- [ ] All exit criteria of Phase 4b covered:
  - Workspace status surfaced in sidebar
  - Updates propagate without manual app restart (via FSEventStream → debounced re-query)
  - jj-first behavior (op_heads change triggers refresh)
- [ ] No new comments anywhere.
- [ ] All builds + tests green.
- [ ] No unrelated changes (focus on probe + watcher + store + badge view + minimal root wiring).
- [ ] No type rename, no persistence change.
