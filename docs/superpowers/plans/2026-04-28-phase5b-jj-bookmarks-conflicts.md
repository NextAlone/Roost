# Phase 5b — jj Panel: Bookmarks + Conflicts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Extend `JjPanelSnapshot` + `JjPanelLoader` + `JjPanelView` with bookmark list and conflict list (read-only). Conflicts use the existing `JjConflictParser` against `jj resolve --list` output.

**Architecture:** Snapshot grows two new fields. Loader gains two new closure-injected loaders (with sensible defaults using `JjBookmarkService.list` + a new `JjConflictsService.list`). View gains a bookmarks section and a conflicts list (replacing the simple banner from 5a).

**Tech Stack:** Swift 6, SwiftUI, swift-testing, existing `JjBookmarkService`, existing `JjConflictParser`.

**Locked decisions:**
- Read-only this phase. No bookmark CRUD UI (Phase 5d).
- New service `JjConflictsService` (singular `Conflict` + `s` suffix consistent with `JjBookmarkService`) wrapping `jj resolve --list`. Tests via injected runner closure, mirrors existing service pattern.
- The conflict banner from 5a is replaced by a list of conflicted files.
- Bookmark display: name + change-id prefix + (local/remote-only) marker.

**Out of scope:**
- Bookmark mutations (create/delete/move) — Phase 5d.
- Conflict resolution mutations — Phase 5c+.
- Bookmark filtering/search.
- Remote bookmark grouping.

---

## File Structure

**Create:**
- `Muxy/Services/Jj/JjConflictsService.swift`
- `Tests/MuxyTests/Services/Jj/JjConflictsServiceTests.swift`

**Modify:**
- `Muxy/Models/JjPanelSnapshot.swift` — add `bookmarks: [JjBookmark]`, `conflicts: [JjConflict]`
- `Muxy/Services/Jj/JjPanelLoader.swift` — add two new closure params with defaults
- `Tests/MuxyTests/Services/Jj/JjPanelLoaderTests.swift` — extend tests
- `Muxy/Views/VCS/JjPanelView.swift` — add bookmarks section + conflicts list

---

## Task 1: JjConflictsService

**Files:**
- Create: `Muxy/Services/Jj/JjConflictsService.swift`
- Test: `Tests/MuxyTests/Services/Jj/JjConflictsServiceTests.swift`

- [ ] **Step 1: Inspect existing service pattern**

```bash
cat Muxy/Services/Jj/JjBookmarkService.swift
```

Note the `JjRunFn` typealias (a closure type). Use the same shape.

- [ ] **Step 2: Write failing test**

Create `Tests/MuxyTests/Services/Jj/JjConflictsServiceTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("JjConflictsService")
struct JjConflictsServiceTests {
    @Test("parses 'jj resolve --list' output into conflicts")
    func parses() async throws {
        let stdout = "Cargo.toml    2-sided conflict\nREADME.md    2-sided conflict\n"
        let runner: JjRunFn = { _, _, _, _ in
            JjProcessResult(
                status: 0,
                stdout: Data(stdout.utf8),
                stderr: ""
            )
        }
        let service = JjConflictsService(queue: JjProcessQueue.shared, runner: runner)
        let conflicts = try await service.list(repoPath: "/tmp/wt")
        #expect(conflicts.map(\.path) == ["Cargo.toml", "README.md"])
    }

    @Test("non-zero exit throws")
    func nonZeroExit() async {
        let runner: JjRunFn = { _, _, _, _ in
            JjProcessResult(status: 1, stdout: Data(), stderr: "boom")
        }
        let service = JjConflictsService(queue: JjProcessQueue.shared, runner: runner)
        await #expect(throws: (any Error).self) {
            _ = try await service.list(repoPath: "/tmp/wt")
        }
    }

    @Test("empty stdout → empty list")
    func emptyOutput() async throws {
        let runner: JjRunFn = { _, _, _, _ in
            JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        let service = JjConflictsService(queue: JjProcessQueue.shared, runner: runner)
        let conflicts = try await service.list(repoPath: "/tmp/wt")
        #expect(conflicts.isEmpty)
    }
}
```

If the existing `JjProcessResult` type uses different field names (likely it's the type returned by `JjProcessRunner.run`), grep to find the actual signature: `grep -n "struct JjProcessResult\|init.*status:.*stdout" Muxy/Services/Jj/`. Adapt the test accordingly.

- [ ] **Step 3: Run, expect failure**

```bash
swift test --filter JjConflictsServiceTests
```

- [ ] **Step 4: Implement**

Create `Muxy/Services/Jj/JjConflictsService.swift`:

```swift
import Foundation
import MuxyShared

struct JjConflictsService: Sendable {
    private let queue: JjProcessQueue
    private let runner: JjRunFn

    init(queue: JjProcessQueue, runner: @escaping JjRunFn = { repoPath, command, snapshot, atOp in
        try await JjProcessRunner.run(
            repoPath: repoPath,
            command: command,
            snapshot: snapshot,
            atOp: atOp
        )
    }) {
        self.queue = queue
        self.runner = runner
    }

    func list(repoPath: String) async throws -> [JjConflict] {
        let result = try await runner(
            repoPath,
            ["resolve", "--list"],
            .ignore,
            nil
        )
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return JjConflictParser.parse(raw)
    }
}
```

The `JjProcessError.nonZeroExit` and `JjRunFn` typealias both exist (see `JjBookmarkService.swift`). Verify by reading that file.

- [ ] **Step 5: Run targeted + full**

```bash
swift test --filter JjConflictsServiceTests
swift test 2>&1 | tail -3
```

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(jj): JjConflictsService wraps 'jj resolve --list'"
```

---

## Task 2: Extend JjPanelSnapshot with bookmarks + conflicts

**Files:**
- Modify: `Muxy/Models/JjPanelSnapshot.swift`

- [ ] **Step 1: Replace the struct**

```swift
import Foundation
import MuxyShared

struct JjPanelSnapshot: Sendable {
    let show: JjShowOutput
    let parentDiff: [JjStatusEntry]
    let status: JjStatus
    let bookmarks: [JjBookmark]
    let conflicts: [JjConflict]
}
```

- [ ] **Step 2: Build (this will fail at JjPanelLoader.load callsite)**

```bash
swift build 2>&1 | tail -10
```

Expected: compile errors at `JjPanelLoader.load(...)` because the snapshot init no longer matches. We fix that in Task 3.

- [ ] **Step 3: Commit (skip if build broken — combine with Task 3)**

Don't commit yet — wait until Task 3 fixes the loader. Move to Task 3.

---

## Task 3: Extend JjPanelLoader

**Files:**
- Modify: `Muxy/Services/Jj/JjPanelLoader.swift`
- Modify: `Tests/MuxyTests/Services/Jj/JjPanelLoaderTests.swift`

- [ ] **Step 1: Update tests**

In `Tests/MuxyTests/Services/Jj/JjPanelLoaderTests.swift`, modify the existing test that constructs a `JjPanelLoader(...)` to also pass `bookmarksLoader:` and `conflictsLoader:`. Replace the file's first test body:

```swift
    @Test("composes show + status + summary + bookmarks + conflicts into a snapshot")
    func composes() async throws {
        let change = JjChangeId(prefix: "ab", full: "abcdef")
        let show = JjShowOutput(
            change: change,
            parents: [],
            description: "demo",
            diffStat: nil
        )
        let entry = JjStatusEntry(change: .modified, path: "README.md")
        let status = JjStatus(
            workingCopy: change,
            parent: nil,
            workingCopySummary: "",
            entries: [entry],
            hasConflicts: false
        )
        let parentDiff = [entry]
        let bookmark = JjBookmark(name: "main", target: change, isLocal: true, remotes: [])
        let conflict = JjConflict(path: "README.md")

        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            summaryLoader: { _, _ in parentDiff },
            bookmarksLoader: { _ in [bookmark] },
            conflictsLoader: { _ in [conflict] }
        )
        let snapshot = try await loader.load(repoPath: "/tmp/wt")
        #expect(snapshot.show.description == "demo")
        #expect(snapshot.parentDiff.count == 1)
        #expect(snapshot.status.entries.count == 1)
        #expect(snapshot.bookmarks.count == 1)
        #expect(snapshot.conflicts.first?.path == "README.md")
    }
```

The error-propagation test stays unchanged (`statusLoader` etc. still receive `fatalError("not reached")` defaults). Update its loader construction to add the two new closures with `fatalError` placeholders so it still compiles:

```swift
    @Test("propagates show errors")
    func propagatesShowError() async {
        struct Boom: Error {}
        let loader = JjPanelLoader(
            showLoader: { _ in throw Boom() },
            statusLoader: { _ in fatalError("not reached") },
            summaryLoader: { _, _ in fatalError("not reached") },
            bookmarksLoader: { _ in fatalError("not reached") },
            conflictsLoader: { _ in fatalError("not reached") }
        )
        await #expect(throws: Boom.self) {
            try await loader.load(repoPath: "/tmp/wt")
        }
    }
```

- [ ] **Step 2: Update `JjPanelLoader`**

In `Muxy/Services/Jj/JjPanelLoader.swift`, extend:

```swift
import Foundation
import MuxyShared

struct JjPanelLoader: Sendable {
    private let showLoader: @Sendable (String) async throws -> JjShowOutput
    private let statusLoader: @Sendable (String) async throws -> JjStatus
    private let summaryLoader: @Sendable (String, String) async throws -> [JjStatusEntry]
    private let bookmarksLoader: @Sendable (String) async throws -> [JjBookmark]
    private let conflictsLoader: @Sendable (String) async throws -> [JjConflict]

    init(
        showLoader: @escaping @Sendable (String) async throws -> JjShowOutput = Self.defaultShow,
        statusLoader: @escaping @Sendable (String) async throws -> JjStatus = Self.defaultStatus,
        summaryLoader: @escaping @Sendable (String, String) async throws -> [JjStatusEntry] = Self.defaultSummary,
        bookmarksLoader: @escaping @Sendable (String) async throws -> [JjBookmark] = Self.defaultBookmarks,
        conflictsLoader: @escaping @Sendable (String) async throws -> [JjConflict] = Self.defaultConflicts
    ) {
        self.showLoader = showLoader
        self.statusLoader = statusLoader
        self.summaryLoader = summaryLoader
        self.bookmarksLoader = bookmarksLoader
        self.conflictsLoader = conflictsLoader
    }

    func load(repoPath: String) async throws -> JjPanelSnapshot {
        let show = try await showLoader(repoPath)
        let status = try await statusLoader(repoPath)
        let parentDiff = (try? await summaryLoader(repoPath, "@-")) ?? []
        let bookmarks = (try? await bookmarksLoader(repoPath)) ?? []
        let conflicts = status.hasConflicts ? ((try? await conflictsLoader(repoPath)) ?? []) : []
        return JjPanelSnapshot(
            show: show,
            parentDiff: parentDiff,
            status: status,
            bookmarks: bookmarks,
            conflicts: conflicts
        )
    }

    // existing defaultShow / defaultStatus / defaultSummary stay unchanged

    private static let defaultBookmarks: @Sendable (String) async throws -> [JjBookmark] = { repoPath in
        try await JjBookmarkService(queue: JjProcessQueue.shared).list(repoPath: repoPath)
    }

    private static let defaultConflicts: @Sendable (String) async throws -> [JjConflict] = { repoPath in
        try await JjConflictsService(queue: JjProcessQueue.shared).list(repoPath: repoPath)
    }
}
```

The conflict loader is conditionally invoked — only when `status.hasConflicts` is true — to avoid the extra subprocess in the common case.

- [ ] **Step 3: Run tests**

```bash
swift test --filter JjPanelLoaderTests
swift test 2>&1 | tail -3
```

Expected: 2 tests pass, total all green.

- [ ] **Step 4: Commit (combines snapshot extension + loader extension)**

```bash
jj commit -m "feat(jj): JjPanelLoader/Snapshot include bookmarks + conflicts"
```

---

## Task 4: Render bookmarks + conflicts in JjPanelView

**Files:**
- Modify: `Muxy/Views/VCS/JjPanelView.swift`

- [ ] **Step 1: Add bookmark + conflict sections**

In `JjPanelView.body`, the current rendering shows: header, changeCard, divider, fileList, optional conflictBanner. Replace the conflict banner with a list, and add a bookmark list section.

Replace the body's snapshot branch:

```swift
            if let snapshot = state.snapshot {
                changeCard(snapshot: snapshot)
                Divider()
                fileList(entries: snapshot.parentDiff)
                if !snapshot.bookmarks.isEmpty {
                    bookmarkList(bookmarks: snapshot.bookmarks)
                }
                if !snapshot.conflicts.isEmpty {
                    conflictList(conflicts: snapshot.conflicts)
                }
            } else if let error = state.errorMessage {
                ...
```

Then add two new helper methods (keep all existing helpers):

```swift
    private func bookmarkList(bookmarks: [JjBookmark]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Bookmarks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
                Text("(\(bookmarks.count))")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(bookmarks, id: \.name) { bookmark in
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 9))
                            .foregroundStyle(MuxyTheme.accent)
                            .frame(width: 12)
                        Text(bookmark.name)
                            .font(.system(size: 11))
                            .foregroundStyle(MuxyTheme.fg)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let target = bookmark.target {
                            Text(target.prefix)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MuxyTheme.fgDim)
                        }
                        if !bookmark.isLocal, !bookmark.remotes.isEmpty {
                            Text("(\(bookmark.remotes.joined(separator: ",")))")
                                .font(.system(size: 9))
                                .foregroundStyle(MuxyTheme.fgDim)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func conflictList(conflicts: [JjConflict]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.diffRemoveFg)
                Text("Conflicts")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.diffRemoveFg)
                Text("(\(conflicts.count))")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(conflicts, id: \.path) { conflict in
                    Text(conflict.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(MuxyTheme.fg)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(8)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
    }
```

The old `conflictBanner` helper can be removed (it's replaced by `conflictList`). DO leave unused if removal would require a cascade; just don't reference it. Cleanest: delete the unused helper.

- [ ] **Step 2: Build + test**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(jj): JjPanelView renders bookmark + conflict lists"
```

---

## Task 5: Migration plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append after Phase 5a status block**

After the existing 5a status block in the Phase 5 section, append:

```markdown
**Status (2026-04-28): Phase 5b (bookmarks + conflicts) landed.**

- `JjConflictsService` wraps `jj resolve --list`; uses existing `JjConflictParser`.
- `JjPanelSnapshot` adds `bookmarks: [JjBookmark]` + `conflicts: [JjConflict]`.
- `JjPanelLoader` lazily fetches conflicts only when `status.hasConflicts == true` (avoids extra subprocess in common case).
- `JjPanelView` renders bookmark list (with target prefix + remote markers) and conflict list. The old conflict banner is removed.
- Mutating actions (5c, 5d) → upcoming.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(plan): mark Phase 5b (bookmarks + conflicts) landed"
```

---

## Self-Review Checklist

- [ ] Bookmark / conflict reads work via injected closures in tests.
- [ ] Conflict list only fetched when status.hasConflicts == true.
- [ ] No mutating UI yet.
- [ ] No comments added.
- [ ] All tests + build green.
