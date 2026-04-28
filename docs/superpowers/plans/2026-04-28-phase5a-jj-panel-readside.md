# Phase 5a — jj Panel: Read-Side Data + Basic UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Replace the `jjPlaceholder` in `VCSTabView` with a real `JjPanelView` that shows the current change (id + description), parent diff summary, and dirty/conflicted status for jj projects. Read-only — mutating actions land in 5c/5d.

**Architecture:** Add `JjPanelState` (@Observable @MainActor) holding the snapshot, plus `JjPanelLoader` (Sendable service) that composes `JjRepositoryService.show` + `JjStatusService` + `JjDiffService`. `VCSTabState` lazy-creates `jjState: JjPanelState?` when `vcsKind == .jj` and refreshes it on directory watcher tick. `JjPanelView` renders the snapshot.

**Tech Stack:** Swift 6, SwiftUI, swift-testing, existing `Muxy/Services/Jj/*`.

**Locked decisions:**
- Read-only this phase. No mutating actions.
- New separate state object (`JjPanelState`) — avoids piling more onto the 1200-line git-first `VCSTabState`. The git path stays untouched.
- `VCSTabState.refresh()` dispatches by `vcsKind` — for `.jj`, reload the `jjState`; for `.git`, existing path. Already partly in place from Phase 2.2e; extend.
- Loader API: `JjPanelLoader.load(repoPath:) async throws -> JjPanelSnapshot` returning a value type; closure-injectable for tests.
- Diff revset: `@-` (parent of working copy) — shows the working-copy change vs its parent. Matches typical "what's in the current change" mental model.

**Out of scope:**
- Bookmarks (Phase 5b).
- Conflict list rendering with detail (Phase 5b — basic flag from JjStatus is enough here).
- Mutating actions (Phase 5c/5d).
- Diff preview content / hunks (Phase 5c+ if needed).
- DAG view (Phase 5+ later, not in scope per migration plan minimum features).

---

## File Structure

**Create:**
- `Muxy/Models/JjPanelSnapshot.swift` — value type with all read-side data
- `Muxy/Models/JjPanelState.swift` — `@Observable @MainActor final class`, holds snapshot + loading flags
- `Muxy/Services/Jj/JjPanelLoader.swift` — composes show + status + diff queries
- `Muxy/Views/VCS/JjPanelView.swift` — SwiftUI view rendering the snapshot
- `Tests/MuxyTests/Services/Jj/JjPanelLoaderTests.swift`
- `Tests/MuxyTests/Models/JjPanelStateTests.swift`

**Modify:**
- `Muxy/Models/VCSTabState.swift` — own `jjState: JjPanelState?`; lazy-create on first access; dispatch `refresh()` by `vcsKind`
- `Muxy/Views/VCS/VCSTabView.swift` — replace `jjPlaceholder` rendering with `JjPanelView(state: state.jjStateOrCreate())` (or similar accessor)

---

## Task 1: JjPanelSnapshot value type

**Files:**
- Create: `Muxy/Models/JjPanelSnapshot.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import MuxyShared

struct JjPanelSnapshot: Sendable, Equatable {
    let show: JjShowOutput
    let parentDiff: [JjStatusEntry]
    let status: JjStatus
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected SUCCESS.

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(jj): JjPanelSnapshot value type"
```

No tests required — pure value type, all fields are existing types.

---

## Task 2: JjPanelLoader

**Files:**
- Create: `Muxy/Services/Jj/JjPanelLoader.swift`
- Test: `Tests/MuxyTests/Services/Jj/JjPanelLoaderTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("JjPanelLoader")
struct JjPanelLoaderTests {
    @Test("composes show + status + summary into a snapshot")
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

        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            summaryLoader: { _, _ in parentDiff }
        )
        let snapshot = try await loader.load(repoPath: "/tmp/wt")
        #expect(snapshot.show.description == "demo")
        #expect(snapshot.parentDiff.count == 1)
        #expect(snapshot.status.entries.count == 1)
    }

    @Test("propagates show errors")
    func propagatesShowError() async {
        struct Boom: Error {}
        let loader = JjPanelLoader(
            showLoader: { _ in throw Boom() },
            statusLoader: { _ in fatalError("not reached") },
            summaryLoader: { _, _ in fatalError("not reached") }
        )
        await #expect(throws: Boom.self) {
            try await loader.load(repoPath: "/tmp/wt")
        }
    }
}
```

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter JjPanelLoaderTests
```

- [ ] **Step 3: Implement**

Create `Muxy/Services/Jj/JjPanelLoader.swift`:

```swift
import Foundation
import MuxyShared

struct JjPanelLoader: Sendable {
    private let showLoader: @Sendable (String) async throws -> JjShowOutput
    private let statusLoader: @Sendable (String) async throws -> JjStatus
    private let summaryLoader: @Sendable (String, String) async throws -> [JjStatusEntry]

    init(
        showLoader: @escaping @Sendable (String) async throws -> JjShowOutput = Self.defaultShow,
        statusLoader: @escaping @Sendable (String) async throws -> JjStatus = Self.defaultStatus,
        summaryLoader: @escaping @Sendable (String, String) async throws -> [JjStatusEntry] = Self.defaultSummary
    ) {
        self.showLoader = showLoader
        self.statusLoader = statusLoader
        self.summaryLoader = summaryLoader
    }

    func load(repoPath: String) async throws -> JjPanelSnapshot {
        let show = try await showLoader(repoPath)
        let status = try await statusLoader(repoPath)
        let parentDiff = (try? await summaryLoader(repoPath, "@-")) ?? []
        return JjPanelSnapshot(show: show, parentDiff: parentDiff, status: status)
    }

    private static let defaultShow: @Sendable (String) async throws -> JjShowOutput = { repoPath in
        try await JjRepositoryService.shared.show(repoPath: repoPath, revset: "@")
    }

    private static let defaultStatus: @Sendable (String) async throws -> JjStatus = { repoPath in
        let result = try await JjProcessRunner.run(
            repoPath: repoPath,
            command: ["status"],
            snapshot: .ignore
        )
        guard result.status == 0 else {
            throw JjPanelLoaderError.statusFailed(stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjStatusParser.parse(raw)
    }

    private static let defaultSummary: @Sendable (String, String) async throws -> [JjStatusEntry] = { repoPath, revset in
        try await JjDiffService.shared.summary(repoPath: repoPath, revset: revset)
    }
}

enum JjPanelLoaderError: Error, Sendable {
    case statusFailed(stderr: String)
}
```

If `JjRepositoryService.shared`, `JjDiffService.shared`, or `JjProcessRunner.run` have different signatures than what's shown, adapt — read the existing service files to verify exact APIs. The intent is: load `jj show @` → `JjShowOutput`; load `jj status` → `JjStatus`; load `jj diff --summary -r @-` → `[JjStatusEntry]`.

- [ ] **Step 4: Run targeted + full**

```bash
swift test --filter JjPanelLoaderTests
swift test 2>&1 | tail -3
```

Expected: 2 new tests + total green.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): JjPanelLoader composes show + status + summary"
```

---

## Task 3: JjPanelState

**Files:**
- Create: `Muxy/Models/JjPanelState.swift`
- Test: `Tests/MuxyTests/Models/JjPanelStateTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("JjPanelState")
struct JjPanelStateTests {
    @Test("starts with no snapshot and not loading")
    func initialState() {
        let state = JjPanelState(repoPath: "/tmp/wt")
        #expect(state.snapshot == nil)
        #expect(state.isLoading == false)
        #expect(state.errorMessage == nil)
    }

    @Test("refresh populates snapshot")
    func refreshPopulates() async {
        let change = JjChangeId(prefix: "ab", full: "abcdef")
        let show = JjShowOutput(change: change, parents: [], description: "x", diffStat: nil)
        let status = JjStatus(workingCopy: change, parent: nil, workingCopySummary: "", entries: [], hasConflicts: false)
        let snapshot = JjPanelSnapshot(show: show, parentDiff: [], status: status)
        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            summaryLoader: { _, _ in [] }
        )
        let state = JjPanelState(repoPath: "/tmp/wt", loader: loader)
        await state.refresh()
        #expect(state.snapshot == snapshot)
        #expect(state.isLoading == false)
        #expect(state.errorMessage == nil)
    }

    @Test("refresh on error sets errorMessage and clears loading")
    func refreshError() async {
        struct Boom: Error, CustomStringConvertible { var description: String { "boom" } }
        let loader = JjPanelLoader(
            showLoader: { _ in throw Boom() },
            statusLoader: { _ in fatalError() },
            summaryLoader: { _, _ in fatalError() }
        )
        let state = JjPanelState(repoPath: "/tmp/wt", loader: loader)
        await state.refresh()
        #expect(state.snapshot == nil)
        #expect(state.errorMessage == "boom")
        #expect(state.isLoading == false)
    }
}
```

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter JjPanelStateTests
```

- [ ] **Step 3: Implement**

Create `Muxy/Models/JjPanelState.swift`:

```swift
import Foundation
import MuxyShared
import Observation

@MainActor
@Observable
final class JjPanelState {
    let repoPath: String
    private(set) var snapshot: JjPanelSnapshot?
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    private let loader: JjPanelLoader

    init(repoPath: String, loader: JjPanelLoader = JjPanelLoader()) {
        self.repoPath = repoPath
        self.loader = loader
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await loader.load(repoPath: repoPath)
            snapshot = result
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
```

- [ ] **Step 4: Run targeted + full**

```bash
swift test --filter JjPanelStateTests
swift test 2>&1 | tail -3
```

Expected: 3 new tests + total green.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): JjPanelState observable wrapper around loader"
```

---

## Task 4: VCSTabState owns jjState (lazy)

**Files:**
- Modify: `Muxy/Models/VCSTabState.swift`

- [ ] **Step 1: Inspect**

```bash
grep -n "vcsKind\|var watcher\|func refresh\b" Muxy/Models/VCSTabState.swift | head -15
```

Find:
- The existing `vcsKind` field (added in Phase 2.2e).
- The existing `refresh()` (or `refreshFromGit`/etc.) method.
- The existing watcher's handler.

- [ ] **Step 2: Add a stored property**

In `VCSTabState`, add (near other stored properties):

```swift
    @ObservationIgnored private var _jjState: JjPanelState?

    var jjState: JjPanelState? {
        guard vcsKind == .jj else { return nil }
        if let existing = _jjState { return existing }
        let created = JjPanelState(repoPath: projectPath)
        _jjState = created
        return created
    }
```

(`@ObservationIgnored` because we don't want `vcsKind` flips to trigger view updates here — the dispatcher in VCSTabView already reads `state.vcsKind`.)

- [ ] **Step 3: Refresh dispatcher**

Find the existing `refresh()` (or equivalent main refresh entry point). Add a `vcsKind` branch at the top:

```swift
    func refresh() {
        if vcsKind == .jj {
            Task { @MainActor in
                await jjState?.refresh()
            }
            return
        }
        // existing git refresh logic continues unchanged
        ...
    }
```

If the existing method isn't named `refresh` exactly, find the watcher-handler entry point and add the same dispatch there. If the method is already async, drop the `Task`. Read carefully before editing.

- [ ] **Step 4: Build + test**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -3
```

Expected: SUCCESS, all green (no behavior change for git path).

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(vcs): VCSTabState lazy-owns jjState + dispatches refresh"
```

---

## Task 5: JjPanelView (basic UI)

**Files:**
- Create: `Muxy/Views/VCS/JjPanelView.swift`
- Modify: `Muxy/Views/VCS/VCSTabView.swift`

- [ ] **Step 1: Create the view**

Create `Muxy/Views/VCS/JjPanelView.swift`:

```swift
import MuxyShared
import SwiftUI

struct JjPanelView: View {
    @Bindable var state: JjPanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let snapshot = state.snapshot {
                changeCard(snapshot: snapshot)
                Divider()
                fileList(entries: snapshot.parentDiff)
                if snapshot.status.hasConflicts {
                    conflictBanner
                }
            } else if let error = state.errorMessage {
                errorBanner(message: error)
            } else if state.isLoading {
                loadingBanner
            } else {
                emptyState
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await state.refresh() }
    }

    private var header: some View {
        HStack {
            Text("Changes")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(state.isLoading)
            .accessibilityLabel("Refresh")
        }
    }

    private func changeCard(snapshot: JjPanelSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(snapshot.show.change.prefix)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MuxyTheme.accent)
                Text(snapshot.show.change.full)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(snapshot.show.description.isEmpty ? "(no description)" : snapshot.show.description)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    private func fileList(entries: [JjStatusEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Files")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
                Text("(\(entries.count))")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
            }
            if entries.isEmpty {
                Text("No changes vs parent")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgDim)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entries, id: \.path) { entry in
                        HStack(spacing: 6) {
                            Text(symbol(for: entry.change))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(color(for: entry.change))
                                .frame(width: 12)
                            Text(entry.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MuxyTheme.fg)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func symbol(for change: JjFileChange) -> String {
        switch change {
        case .added: "A"
        case .modified: "M"
        case .removed: "D"
        case .renamed: "R"
        case .copied: "C"
        }
    }

    private func color(for change: JjFileChange) -> Color {
        switch change {
        case .added, .copied: MuxyTheme.diffAddFg
        case .removed: MuxyTheme.diffRemoveFg
        case .modified, .renamed: MuxyTheme.fgMuted
        }
    }

    private var conflictBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MuxyTheme.diffRemoveFg)
            Text("This change has conflicts")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MuxyTheme.diffRemoveFg)
            Spacer()
        }
        .padding(8)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(MuxyTheme.diffRemoveFg)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.diffRemoveFg)
            Spacer()
        }
        .padding(10)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    private var loadingBanner: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Loading…")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
        }
    }

    private var emptyState: some View {
        Text("No data")
            .font(.system(size: 11))
            .foregroundStyle(MuxyTheme.fgDim)
    }
}
```

If `JjFileChange` enum doesn't have all five cases (`.added`, `.modified`, `.removed`, `.renamed`, `.copied`) — it might only have a subset; check `MuxyShared/Jj/JjModels.swift`. Adjust the `symbol(for:)` and `color(for:)` switches to be exhaustive over whatever cases actually exist.

- [ ] **Step 2: Replace jjPlaceholder dispatch**

In `Muxy/Views/VCS/VCSTabView.swift`, around line 37 the body has:
```swift
            if state.vcsKind == .jj {
                jjPlaceholder
            } else {
                header
                ...
            }
```

Replace `jjPlaceholder` with:
```swift
                if let jjState = state.jjState {
                    JjPanelView(state: jjState)
                } else {
                    jjPlaceholder
                }
```

Keep `jjPlaceholder` as a fallback for the unlikely `nil` case (e.g., a `vcsKind` flip mid-render).

- [ ] **Step 3: Build + test**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -3
```

Manual smoke: open a jj-tracked project's VCS panel — should show the current change card, file list, and refresh button. No conflict banner unless there are conflicts.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(jj): JjPanelView replaces placeholder with change card + file list"
```

---

## Task 6: Migration plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append after the Phase 4 status block, before `## Phase 5: jj Changes Panel` heading, INSIDE the Phase 5 section instead — append at the END of the Phase 5 section's existing prose:**

In the Phase 5 section (around line 423), append:

```markdown
**Status (2026-04-28): Phase 5a (read-side panel) landed.**

- `JjPanelSnapshot` (value type), `JjPanelLoader` (composes `jj show @` + `jj status` + `jj diff --summary -r @-`), `JjPanelState` (@Observable @MainActor) live in `Muxy/Models` / `Muxy/Services/Jj`.
- `VCSTabState` lazy-owns `jjState: JjPanelState?` and dispatches `refresh()` by `vcsKind`.
- `JjPanelView` renders the change card (id + description), file list, conflict banner, and refresh button. Replaces the old `jjPlaceholder`.
- Bookmarks (5b), conflicts detail (5b), and mutating actions (5c, 5d) → upcoming.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(plan): mark Phase 5a (jj panel read-side) landed"
```

---

## Self-Review Checklist

- [ ] No mutation methods.
- [ ] Git path completely untouched (existing tests still green).
- [ ] No comments added.
- [ ] No type rename, no persistence change.
- [ ] `jjPlaceholder` retained as fallback.
- [ ] Refresh wired into existing watcher tick (via `VCSTabState.refresh()`).
