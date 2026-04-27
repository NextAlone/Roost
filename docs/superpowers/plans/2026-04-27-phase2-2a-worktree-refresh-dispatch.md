# Phase 2.2a — WorktreeStore.refresh dispatch by VcsKind

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Read-side routing. WorktreeStore gains a generic `refresh(project:)` that dispatches to `refreshGit` or `refreshJj` by the primary `Worktree.vcsKind`. The git path keeps its existing implementation untouched. The jj path uses `JjWorkspaceService.list` to update tracked Worktrees' `currentChangeId` and prune stale entries by name match. No UI changes; sidebar still consumes the same Worktree list output. Mutating ops (create/remove) are out of scope (Phase 2.2b).

**Architecture:** Inject `JjWorkspaceService` and `JjProcessQueue` into `WorktreeStore` via closures (matching the existing `listGitWorktrees` injection pattern). Add `refreshJj(project:)` analog to `refreshFromGit`. Rename the public refresh contract: keep `refreshFromGit` as the git-specific path (callers shift to the new dispatcher), add `refreshJj`, add a `refresh(project:)` that switches on the primary worktree's `vcsKind`. The single existing caller (`WorktreeRefreshHelper`) calls the new dispatcher.

**Tech Stack:** Swift 6, swift-testing, jj 0.40.

**Out of scope (Phase 2.2b):**
- Worktree create/remove dispatch
- `RemoteServerDelegate.vcsCreateWorktree` controller protocol
- `CreateWorktreeSheet` controller injection
- External jj workspace path discovery (paths unknown without on-disk scan)

---

## Constraints discovered from real jj 0.40

- `jj workspace list` does NOT expose `path()` on `WorkspaceRef` — paths must be inferred from tracked Worktrees, not auto-discovered.
- Output format with template `self.name() ++ "\t" ++ self.target().change_id() ++ "\n"`:
  ```
  default	lknkwurrssvusyunltqlwqmskokmkssk
  feat-m6	qsoqlvuqvlspztkqlkunsoynyzpxkqqp
  ```
- Tracked jj Worktrees in WorktreeStore are matched by **name** (`Worktree.name`) to workspace output. Stale entries (tracked but missing from `jj workspace list`) get pruned.
- External jj workspaces (`source: .external`) created outside Roost won't be auto-imported — their paths can't be deduced. Phase 2.2c can add manual import UI.

---

## File Structure

Modified:
```
Muxy/Services/WorktreeStore.swift              - add JjWorkspaceService injection, refreshJj, refresh dispatcher
Muxy/Services/Jj/JjWorkspaceParser.swift       - extend parser to capture currentChangeId via richer template
Muxy/Services/Jj/JjWorkspaceService.swift      - update list() to use the richer template
Muxy/Views/Sidebar/WorktreeRefreshHelper.swift - call refresh instead of refreshFromGit
Tests/MuxyTests/Jj/JjWorkspaceParserTests.swift - update fixture to richer format
Tests/MuxyTests/Jj/JjWorkspaceServiceTests.swift - update fixture
```

New:
```
Tests/MuxyTests/Services/WorktreeStoreRefreshDispatchTests.swift
```

---

## Conventions

- Internal-by-default. New parser/service members narrow if introducing new types.
- Tests: swift-testing, `@testable import Roost` + `import MuxyShared`.
- Project rule: no comments. jj-only VCS.
- After each commit: `swift test --filter "Jj|Worktree|VcsKind"` should remain green.

---

### Task 1: Extend JjWorkspaceParser to carry change_id

**Files:**
- Modify: `Muxy/Services/Jj/JjWorkspaceParser.swift`
- Modify: `Tests/MuxyTests/Jj/JjWorkspaceParserTests.swift`

The current parser handles `<name>: <change-id-short> <description>` (default jj output). To get a clean change_id without bracket parsing, switch to a tab-separated template: `self.name() ++ "\t" ++ self.target().change_id() ++ "\n"`.

- [ ] **Step 1: Update tests**

Read current `Tests/MuxyTests/Jj/JjWorkspaceParserTests.swift`. Replace its single test with:

```swift
@Test("parses tab-separated template output")
func tabSeparated() throws {
    let raw = """
    default\tlknkwurrssvusyunltqlwqmskokmkssk
    feat-m6\tqsoqlvuqvlspztkqlkunsoynyzpxkqqp
    """
    let entries = try JjWorkspaceParser.parse(raw)
    #expect(entries.count == 2)
    #expect(entries[0].name == "default")
    #expect(entries[0].workingCopy.full == "lknkwurrssvusyunltqlwqmskokmkssk")
    #expect(entries[1].name == "feat-m6")
    #expect(entries[1].workingCopy.full == "qsoqlvuqvlspztkqlkunsoynyzpxkqqp")
}

@Test("rejects malformed line (missing tab)")
func malformed() {
    let raw = "no-tab-line\n"
    #expect(throws: (any Error).self) {
        _ = try JjWorkspaceParser.parse(raw)
    }
}

@Test("empty input returns empty array")
func empty() throws {
    let entries = try JjWorkspaceParser.parse("")
    #expect(entries.isEmpty)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter JjWorkspaceParserTests`
Expected: existing test fails (different format) or compile error if signature changed.

- [ ] **Step 3: Rewrite parser + add template**

Replace `Muxy/Services/Jj/JjWorkspaceParser.swift`:

```swift
import Foundation
import MuxyShared

enum JjWorkspaceParseError: Error, Sendable {
    case malformedLine(String)
}

enum JjWorkspaceParser {
    static let template = #"self.name() ++ "\t" ++ self.target().change_id() ++ "\n""#

    static func parse(_ raw: String) throws -> [JjWorkspaceEntry] {
        var entries: [JjWorkspaceEntry] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw JjWorkspaceParseError.malformedLine(String(line))
            }
            let name = String(parts[0])
            let fullId = String(parts[1])
            entries.append(JjWorkspaceEntry(
                name: name,
                workingCopy: JjChangeId(prefix: String(fullId.prefix(12)), full: fullId)
            ))
        }
        return entries
    }
}
```

The 12-char prefix mimics jj's default `change_id.shortest()` width — sufficient for display.

- [ ] **Step 4: Update JjWorkspaceService.list to inject template**

Read `Muxy/Services/Jj/JjWorkspaceService.swift`. Update the `list` method's command:

```swift
func list(repoPath: String) async throws -> [JjWorkspaceEntry] {
    let result = try await runner(
        repoPath,
        ["workspace", "list", "-T", JjWorkspaceParser.template],
        .ignore,
        nil
    )
    guard result.status == 0 else {
        throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
    }
    let raw = String(data: result.stdout, encoding: .utf8) ?? ""
    return try JjWorkspaceParser.parse(raw)
}
```

(Just adds `-T` + template to the command.)

- [ ] **Step 5: Update JjWorkspaceServiceTests fixture**

Read `Tests/MuxyTests/Jj/JjWorkspaceServiceTests.swift`. The `list` test stub returns hardcoded text. Update its expected output to match the new template format:

```swift
@Test("list parses workspace entries")
func list() async throws {
    let svc = JjWorkspaceService(queue: JjProcessQueue()) { _, _, _, _ in
        JjProcessResult(
            status: 0,
            stdout: Data("default\tabcdef0123456789abcdef0123456789\n".utf8),
            stderr: ""
        )
    }
    let entries = try await svc.list(repoPath: "/repo")
    #expect(entries.count == 1)
    #expect(entries[0].name == "default")
    #expect(entries[0].workingCopy.full == "abcdef0123456789abcdef0123456789")
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter JjWorkspaceParserTests`
Expected: 3/3 pass.

Run: `swift test --filter JjWorkspaceServiceTests`
Expected: 3/3 pass.

Run: `swift test --filter Jj`
Expected: full Jj suite green.

- [ ] **Step 7: Commit**

```bash
jj commit -m "refactor(jj): JjWorkspaceParser uses tab-template with full change_id"
```

---

### Task 2: Inject JjWorkspaceService into WorktreeStore

**Files:**
- Modify: `Muxy/Services/WorktreeStore.swift`

Add a new closure injection `listJjWorkspaces: @Sendable (String) async throws -> [JjWorkspaceEntry]` to `WorktreeStore.init`, alongside the existing `listGitWorktrees`. Default wraps `JjWorkspaceService(queue:).list(repoPath:)`.

- [ ] **Step 1: Read current init**

Read `Muxy/Services/WorktreeStore.swift` lines 1-30 to confirm the existing init shape.

- [ ] **Step 2: Add injection point**

Modify the init. Add a new stored property and parameter (sketch — read the file and adapt the exact init signature):

```swift
private let listJjWorkspaces: @Sendable (String) async throws -> [JjWorkspaceEntry]

init(
    persistence: WorktreePersisting = FileWorktreePersistence(),
    listGitWorktrees: @escaping @Sendable (String) async throws -> [GitWorktreeRecord] = {
        try await GitWorktreeService.shared.listWorktrees(repoPath: $0)
    },
    listJjWorkspaces: @escaping @Sendable (String) async throws -> [JjWorkspaceEntry] = { repoPath in
        let queue = JjProcessQueue()
        let service = JjWorkspaceService(queue: queue)
        return try await service.list(repoPath: repoPath)
    }
) {
    self.persistence = persistence
    self.listGitWorktrees = listGitWorktrees
    self.listJjWorkspaces = listJjWorkspaces
}
```

Adapt to actual init: read the existing init signature first (look at lines 14-22 from earlier survey). Match the exact pattern.

Add `import MuxyShared` to WorktreeStore.swift if not already present (needed for `JjWorkspaceEntry`).

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: clean.

Run: `swift test --filter WorktreeStore`
Expected: existing tests still pass (default closure handles real call paths; tests that construct WorktreeStore with no args get the new default).

- [ ] **Step 4: Commit**

```bash
jj commit -m "refactor(WorktreeStore): inject JjWorkspaceService listing closure"
```

---

### Task 3: refreshJj implementation

**Files:**
- Modify: `Muxy/Services/WorktreeStore.swift`

`refreshJj(project:)` mirrors `refreshFromGit(project:)`'s shape but uses jj output. Key behavior:
- Calls `listJjWorkspaces(project.path)` → `[JjWorkspaceEntry]`
- For tracked `Worktree` entries with matching `name`, update `currentChangeId` from the entry's `workingCopy.full`
- Prune tracked Worktrees whose name doesn't appear in jj output AND `source == .muxy` (don't prune external)
- Primary worktree (project root) is always kept; its `currentChangeId` updates from the entry whose name == "default" or whose path == project.path

- [ ] **Step 1: Add the method**

Append after `refreshFromGit` in `Muxy/Services/WorktreeStore.swift`:

```swift
func refreshJj(project: Project) async throws -> [Worktree] {
    ensurePrimary(for: project)
    let entries = try await listJjWorkspaces(project.path)
    let entriesByName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })

    var list = worktrees[project.id] ?? []
    for index in list.indices {
        let name = list[index].isPrimary ? "default" : list[index].name
        if let entry = entriesByName[name] {
            list[index].currentChangeId = entry.workingCopy.full
        }
    }
    list = list.filter { worktree in
        if worktree.isPrimary { return true }
        if worktree.source == .external { return true }
        let name = worktree.name
        return entriesByName[name] != nil
    }
    let sorted = sortPrimaryFirst(list)
    setWorktrees(sorted, for: project.id)
    save(projectID: project.id)
    return sorted
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(WorktreeStore): refreshJj updates currentChangeId, prunes stale"
```

---

### Task 4: refresh(project:) dispatcher

**Files:**
- Modify: `Muxy/Services/WorktreeStore.swift`

- [ ] **Step 1: Add dispatcher**

Append after `refreshJj` in `Muxy/Services/WorktreeStore.swift`:

```swift
func refresh(project: Project) async throws -> [Worktree] {
    ensurePrimary(for: project)
    let kind = primary(for: project.id)?.vcsKind ?? .default
    switch kind {
    case .git:
        return try await refreshFromGit(project: project)
    case .jj:
        return try await refreshJj(project: project)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(WorktreeStore): refresh(project:) dispatches by VcsKind"
```

---

### Task 5: Wire WorktreeRefreshHelper through dispatcher

**Files:**
- Modify: `Muxy/Views/Sidebar/WorktreeRefreshHelper.swift`

- [ ] **Step 1: Read current helper**

Read `Muxy/Views/Sidebar/WorktreeRefreshHelper.swift` to understand its structure. The known site is line 18:
```swift
let refreshed = try await worktreeStore.refreshFromGit(project: project)
```

- [ ] **Step 2: Replace call**

Change `refreshFromGit(project:)` to `refresh(project:)` at every call site. Likely just the single line above.

- [ ] **Step 3: Build + tests**

Run: `swift build`
Expected: clean.

Run: `swift test --filter Worktree`
Expected: all green.

Run: `swift test`
Expected: only pre-existing unrelated MuxyURLOpenTests failures.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(sidebar): WorktreeRefreshHelper uses VcsKind dispatcher"
```

---

### Task 6: Tests for refreshJj + dispatcher

**Files:**
- Create: `Tests/MuxyTests/Services/WorktreeStoreRefreshDispatchTests.swift`

Two test cases:
1. WorktreeStore configured with stub `listJjWorkspaces` returning entries — `refresh` on a project whose primary has `vcsKind: .jj` should call the jj path and update `currentChangeId`.
2. WorktreeStore with primary `vcsKind: .git` should call git path (verify by stub `listGitWorktrees` being invoked, jj stub NOT being invoked).

- [ ] **Step 1: Write tests**

Create `Tests/MuxyTests/Services/WorktreeStoreRefreshDispatchTests.swift`:

```swift
import Foundation
import Testing
import MuxyShared

@testable import Roost

@MainActor
@Suite("WorktreeStore refresh dispatch")
struct WorktreeStoreRefreshDispatchTests {
    private let fm = FileManager.default

    private func makeTempDir() -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("ws-dispatch-\(UUID().uuidString)")
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("primary .jj routes through jj listing")
    func dispatchesJj() async throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent(".jj"), withIntermediateDirectories: true)

        let gitCalls = ListCallCounter()
        let jjCalls = ListCallCounter()

        let persistence = InMemoryWorktreePersistence()
        let store = WorktreeStore(
            persistence: persistence,
            listGitWorktrees: { _ in
                await gitCalls.bump()
                return []
            },
            listJjWorkspaces: { _ in
                await jjCalls.bump()
                return [
                    JjWorkspaceEntry(
                        name: "default",
                        workingCopy: JjChangeId(prefix: "abcdefabcdef", full: "abcdefabcdef0123456789abcdef")
                    )
                ]
            }
        )

        let project = Project(name: "P", path: dir.path, sortOrder: 0)
        store.ensurePrimary(for: project)
        let refreshed = try await store.refresh(project: project)

        #expect(await jjCalls.value == 1)
        #expect(await gitCalls.value == 0)
        #expect(refreshed.first(where: \.isPrimary)?.currentChangeId == "abcdefabcdef0123456789abcdef")
    }

    @Test("primary .git routes through git listing")
    func dispatchesGit() async throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let gitCalls = ListCallCounter()
        let jjCalls = ListCallCounter()

        let persistence = InMemoryWorktreePersistence()
        let store = WorktreeStore(
            persistence: persistence,
            listGitWorktrees: { _ in
                await gitCalls.bump()
                return []
            },
            listJjWorkspaces: { _ in
                await jjCalls.bump()
                return []
            }
        )

        let project = Project(name: "P", path: dir.path, sortOrder: 0)
        store.ensurePrimary(for: project)
        _ = try await store.refresh(project: project)

        #expect(await gitCalls.value == 1)
        #expect(await jjCalls.value == 0)
    }
}

actor ListCallCounter {
    var value: Int = 0
    func bump() { value += 1 }
}

final class InMemoryWorktreePersistence: WorktreePersisting, @unchecked Sendable {
    private var stored: [UUID: [Worktree]] = [:]
    func loadWorktrees(projectID: UUID) throws -> [Worktree] { stored[projectID] ?? [] }
    func saveWorktrees(_ worktrees: [Worktree], projectID: UUID) throws { stored[projectID] = worktrees }
    func removeWorktrees(projectID: UUID) throws { stored.removeValue(forKey: projectID) }
}
```

NOTE on test scaffolding: if `WorktreeStore` is `@MainActor`-isolated, the test suite needs `@MainActor`. Reading the existing WorktreeStore declaration confirms this. If WorktreeStore isn't @MainActor, drop the suite annotation.

If `InMemoryWorktreePersistence` collides with existing test helpers, rename to `RefreshDispatchTestPersistence`.

If `ListCallCounter` collides, rename to `RefreshDispatchCallCounter`.

- [ ] **Step 2: Run tests**

Run: `swift test --filter WorktreeStoreRefreshDispatchTests`
Expected: 2/2 pass.

Run: `swift test --filter "Worktree|Jj|VcsKind"`
Expected: full set of related suites green.

- [ ] **Step 3: Commit**

```bash
jj commit -m "test(WorktreeStore): VcsKind-dispatch refresh routing"
```

---

### Task 7: Plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append to Phase 2 status block**

Read the current Phase 2 section. Append after the existing Phase 2.1 status note:

```markdown

Phase 2.2a status (2026-04-27):

- `WorktreeStore.refresh(project:)` dispatches by primary `Worktree.vcsKind`. Git path retains existing `refreshFromGit` behavior; new `refreshJj` updates tracked Worktrees' `currentChangeId` from `jj workspace list` and prunes stale `.muxy` entries by name.
- `JjWorkspaceParser` now consumes a tab-separated template (`name\tchange_id`) — gives full 32-char change_id without bracket parsing.
- `WorktreeRefreshHelper` (single existing caller) routed through the dispatcher; no UI behavior change.
- External jj workspace path discovery deferred (Phase 2.2c).
- Phase 2.2b remains: dispatch worktree create/remove via a `VcsWorktreeController` protocol; `RemoteServerDelegate.vcsCreateWorktree` and `CreateWorktreeSheet` consume the controller.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(vcs): note Phase 2.2a (refresh dispatch) landed"
```

---

## Self-Review

**Spec coverage** vs survey/plan:

| Item | Covered by |
|------|-----------|
| Refresh dispatch by vcsKind | Tasks 3 + 4 |
| jj refresh implementation | Task 3 |
| Existing caller (WorktreeRefreshHelper) updated | Task 5 |
| Test coverage for both branches | Task 6 |
| Parser ergonomic upgrade (full change_id, no brackets) | Task 1 |

**Deferred** (Phase 2.2b / 2.2c):
- WorktreeStore.add / WorktreeStore.remove dispatch
- RemoteServerDelegate VCS controller protocol
- CreateWorktreeSheet routing
- WorktreeDTO IPC update
- Sidebar visual jj badge
- External jj workspace import

**Type consistency:** `JjWorkspaceParser.template` defined once and reused by `JjWorkspaceService.list`. `listJjWorkspaces` closure type matches throughout WorktreeStore. `refresh(project:)` returns `[Worktree]` like both branches.

**Placeholder scan:** No TODOs.

---

## Abort criteria

If `WorktreeStore` is `@MainActor`-isolated and adding the new closure parameter cascades into Sendable warnings on every call site, **stop**: pivot to keeping `refreshFromGit` as-is and add a separate top-level `WorktreeRefreshDispatcher` that wraps both paths. The store's existing surface stays unchanged.

If `jj workspace list` with the new template fails on jj < 0.20 in CI, **stop**: gate behavior on `JjVersion.parse(...) >= JjVersion.minimumSupported` before dispatching, fall back to git path on older jj.
