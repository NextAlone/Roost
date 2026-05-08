# jj Side Panel — File Diff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make working-copy file rows in the jj source-control panel openable in a diff tab, matching the Git side hover-toolbar UX.

**Architecture:** New service-layer `JjDiffService.patch` calls `jj diff --git -r <revset> -- <file>` and returns the unified-diff text. A new `JjDiffLoader` parses that text via the existing `GitDiffParser` (already generic over unified-diff) and stores a `DiffCache.LoadedDiff`. A new `JjDiffViewerTabState` (parallel to `DiffViewerTabState`, no `vcs` coupling) owns its own `DiffCache`, `repoPath`, `revset`, `filePath`, and `mode`. `TerminalTab.Content` gains a `.jjDiffViewer` case so `ContentHostLayer` can render a small `JjDiffViewerPane` that reuses `DiffBodyView` / `UnifiedDiffView` / `SplitDiffView` unchanged. `JjPanelView` gets a new `JjFileRow` (its own file) with a hover toolbar (open editor / open diff) and forwards `onOpenDiff` up through `VCSTabView` to `AppState.openJjDiffViewer`.

**Tech Stack:** Swift 6, SwiftUI, swift-testing, existing `Muxy/Services/Jj/*`, `Muxy/Models/DiffCache`, `Muxy/Services/Git/GitDiffParser` (used as a generic unified-diff parser).

**Locked decisions:**
- Two TabStates (`DiffViewerTabState` for git, `JjDiffViewerTabState` for jj). No protocol/source enum. The view layer (`DiffBodyView`/`UnifiedDiffView`/`SplitDiffView`/`DiffCache`/`DiffDisplayRow`) stays shared and untouched.
- `GitDiffParser` is reused as-is. It is a misnomer (it parses generic unified-diff). Renaming is out of scope for this change.
- jj patch revset: working-copy `@`. Other revsets (changes section, etc.) are out of scope.
- Hover toolbar matches the Git `FileRow` shape but exposes only Open-in-Editor and Open-Diff icons. jj has no stage/discard concept.
- jj file list stays flat — no folder grouping (Git's `FolderRow` is out of scope here).
- Tab dedupe key for jj: `(repoPath, revset, filePath)`. Not `isStaged`.
- Snapshot/restore of jj diff tabs is intentionally not persisted — mirror the existing `.diffViewer` behavior (`TerminalTab.swift:137` restores as terminal placeholder).

**Out of scope:**
- Renaming `GitDiffParser`.
- jj folder tree / grouping.
- Diffing arbitrary commits from the changes section.
- Persisting jj diff tabs across restart.
- Stage/unstage/discard semantics in jj.

---

## File Structure

**Create:**
- `Muxy/Models/JjDiffViewerTabState.swift`
- `Muxy/Services/Jj/JjDiffLoader.swift`
- `Muxy/Views/VCS/JjDiffViewerPane.swift`
- `Muxy/Views/VCS/JjFileRow.swift`
- `Tests/MuxyTests/Services/Jj/JjDiffServiceTests.swift`
- `Tests/MuxyTests/Services/Jj/JjDiffLoaderTests.swift`
- `Tests/MuxyTests/Models/JjDiffViewerTabStateTests.swift`

**Modify:**
- `Muxy/Services/Jj/JjDiffService.swift` — add `patch(repoPath:revset:filePath:lineLimit:) async throws -> String`
- `Muxy/Models/TerminalTab.swift` — add `.jjDiffViewer` case + `Kind.jjDiffViewer` + accessor + restore stub
- `Muxy/Models/TabArea.swift` — `createJjDiffViewerTab(repoPath:revset:filePath:)`
- `Muxy/Models/AppState.swift` — `openJjDiffViewer(repoPath:revset:filePath:projectID:)` + `JjDiffViewerRequest` + new action
- `Muxy/Models/WorkspaceReducer/TabReducer.swift` — handle the new action
- `Muxy/Views/Workspace/ContentHostLayer.swift` — render `.jjDiffViewer` entries
- `Muxy/Views/VCS/JjPanelView.swift` — add `onOpenDiff` parameter; replace inline `fileListContent` body with `JjFileRow`
- `Muxy/Views/VCS/VCSTabView.swift` — pass `onOpenDiff` into `JjPanelView` calling `appState.openJjDiffViewer(...)`

---

## Task 1: `JjDiffService.patch`

**Files:**
- Modify: `Muxy/Services/Jj/JjDiffService.swift`
- Create: `Tests/MuxyTests/Services/Jj/JjDiffServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MuxyTests/Services/Jj/JjDiffServiceTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("JjDiffService.patch")
struct JjDiffServicePatchTests {
    @Test("invokes jj diff --git with revset and path")
    func invokesCorrectCommand() async throws {
        var captured: [String] = []
        let runner: JjRunFn = { _, command, _, _ in
            captured = command
            return JjProcessResult(
                status: 0,
                stdout: Data("diff --git a/x b/x\n".utf8),
                stderr: ""
            )
        }
        let service = JjDiffService(runner: runner)
        let raw = try await service.patch(
            repoPath: "/tmp/repo",
            revset: "@",
            filePath: "Sources/Foo.swift",
            lineLimit: nil
        )
        #expect(captured == ["diff", "--git", "-r", "@", "--", "Sources/Foo.swift"])
        #expect(raw == "diff --git a/x b/x\n")
    }

    @Test("propagates non-zero exit as JjProcessError")
    func propagatesError() async {
        let runner: JjRunFn = { _, _, _, _ in
            JjProcessResult(status: 1, stdout: Data(), stderr: "boom")
        }
        let service = JjDiffService(runner: runner)
        await #expect(throws: JjProcessError.self) {
            _ = try await service.patch(
                repoPath: "/tmp/repo",
                revset: "@",
                filePath: "x",
                lineLimit: nil
            )
        }
    }

    @Test("truncates stdout to lineLimit lines")
    func truncatesByLineLimit() async throws {
        let big = (0..<5).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let runner: JjRunFn = { _, _, _, _ in
            JjProcessResult(status: 0, stdout: Data(big.utf8), stderr: "")
        }
        let service = JjDiffService(runner: runner)
        let result = try await service.patch(
            repoPath: "/tmp/repo",
            revset: "@",
            filePath: "x",
            lineLimit: 2
        )
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count <= 3)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter RoostTests.JjDiffServicePatchTests 2>&1 | tail -20
```

Expected: FAIL — `patch` method does not exist on `JjDiffService`.

- [ ] **Step 3: Add `patch` to `JjDiffService.swift`**

Edit `Muxy/Services/Jj/JjDiffService.swift`. Add this method inside `struct JjDiffService`:

```swift
    func patch(
        repoPath: String,
        revset: String,
        filePath: String,
        lineLimit: Int?
    ) async throws -> String {
        let result = try await runner(
            repoPath,
            ["diff", "--git", "-r", revset, "--", filePath],
            .ignore,
            nil
        )
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        guard let lineLimit, lineLimit > 0 else { return raw }
        var seen = 0
        var endIndex = raw.startIndex
        while seen < lineLimit, endIndex < raw.endIndex {
            if let nl = raw[endIndex...].firstIndex(of: "\n") {
                endIndex = raw.index(after: nl)
                seen += 1
            } else {
                endIndex = raw.endIndex
                break
            }
        }
        return String(raw[..<endIndex])
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter RoostTests.JjDiffServicePatchTests 2>&1 | tail -10
```

Expected: PASS (3 tests).

- [ ] **Step 5: Lint + build**

```bash
scripts/checks.sh --fix 2>&1 | tail -10
swift build 2>&1 | tail -5
```

Expected: SUCCESS.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(jj): add JjDiffService.patch returning unified-diff text"
```

---

## Task 2: `JjDiffLoader`

**Files:**
- Create: `Muxy/Services/Jj/JjDiffLoader.swift`
- Create: `Tests/MuxyTests/Services/Jj/JjDiffLoaderTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MuxyTests/Services/Jj/JjDiffLoaderTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("JjDiffLoader")
struct JjDiffLoaderTests {
    @Test("stores parsed diff in cache on success")
    func storesParsedDiff() async throws {
        let cache = DiffCache()
        let patch = """
        diff --git a/x b/x
        --- a/x
        +++ b/x
        @@ -1,1 +1,2 @@
         a
        +b
        """
        let service = JjDiffService(runner: { _, _, _, _ in
            JjProcessResult(status: 0, stdout: Data(patch.utf8), stderr: "")
        })
        let request = JjDiffLoader.Request(
            repoPath: "/tmp/r",
            revset: "@",
            filePath: "x",
            forceFull: false
        )
        JjDiffLoader.load(request, cache: cache, service: service)
        try await waitUntil { cache.diff(for: "x") != nil || cache.error(for: "x") != nil }
        let diff = try #require(cache.diff(for: "x"))
        #expect(diff.additions == 1)
        #expect(diff.deletions == 0)
        #expect(diff.rows.isEmpty == false)
        #expect(diff.truncated == false)
    }

    @Test("stores error message on non-zero exit")
    func storesError() async throws {
        let cache = DiffCache()
        let service = JjDiffService(runner: { _, _, _, _ in
            JjProcessResult(status: 1, stdout: Data(), stderr: "no such file")
        })
        let request = JjDiffLoader.Request(
            repoPath: "/tmp/r",
            revset: "@",
            filePath: "missing",
            forceFull: false
        )
        JjDiffLoader.load(request, cache: cache, service: service)
        try await waitUntil { cache.error(for: "missing") != nil }
        let message = try #require(cache.error(for: "missing"))
        #expect(message.isEmpty == false)
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("waitUntil timed out")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter RoostTests.JjDiffLoaderTests 2>&1 | tail -20
```

Expected: FAIL — `JjDiffLoader` does not exist.

- [ ] **Step 3: Implement `JjDiffLoader`**

Create `Muxy/Services/Jj/JjDiffLoader.swift`:

```swift
import Foundation

@MainActor
enum JjDiffLoader {
    static let previewLineLimit = 20000

    struct Request {
        let repoPath: String
        let revset: String
        let filePath: String
        let forceFull: Bool
    }

    static func load(
        _ request: Request,
        cache: DiffCache,
        service: JjDiffService = JjDiffService()
    ) {
        cache.markLoading(request.filePath)
        let lineLimit = request.forceFull ? nil : previewLineLimit
        let task = Task { @MainActor in
            do {
                let raw = try await service.patch(
                    repoPath: request.repoPath,
                    revset: request.revset,
                    filePath: request.filePath,
                    lineLimit: lineLimit
                )
                guard !Task.isCancelled else { return }
                let parsed = GitDiffParser.parseRows(raw)
                let truncated = lineLimit != nil && countLines(raw) >= lineLimit!
                cache.store(
                    DiffCache.LoadedDiff(
                        rows: GitDiffParser.collapseContextRows(parsed.rows),
                        additions: parsed.additions,
                        deletions: parsed.deletions,
                        truncated: truncated
                    ),
                    for: request.filePath,
                    pinnedPaths: []
                )
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                cache.storeError(message, for: request.filePath)
            }
        }
        cache.registerTask(task, for: request.filePath)
    }

    private static func countLines(_ text: String) -> Int {
        text.reduce(into: 0) { count, ch in if ch == "\n" { count += 1 } }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter RoostTests.JjDiffLoaderTests 2>&1 | tail -10
```

Expected: PASS.

- [ ] **Step 5: Lint + build**

```bash
scripts/checks.sh --fix 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(jj): add JjDiffLoader using GitDiffParser to populate DiffCache"
```

---

## Task 3: `JjDiffViewerTabState`

**Files:**
- Create: `Muxy/Models/JjDiffViewerTabState.swift`
- Create: `Tests/MuxyTests/Models/JjDiffViewerTabStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MuxyTests/Models/JjDiffViewerTabStateTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("JjDiffViewerTabState")
struct JjDiffViewerTabStateTests {
    @Test("displayTitle returns last path component")
    func displayTitle() {
        let state = JjDiffViewerTabState(
            repoPath: "/tmp/r",
            revset: "@",
            filePath: "Sources/Foo/Bar.swift"
        )
        #expect(state.displayTitle == "Bar.swift")
    }

    @Test("init triggers a load via injected service")
    func loadsOnInit() async throws {
        var calls = 0
        let service = JjDiffService(runner: { _, _, _, _ in
            calls += 1
            return JjProcessResult(status: 0, stdout: Data("diff --git a/x b/x\n".utf8), stderr: "")
        })
        let state = JjDiffViewerTabState(
            repoPath: "/tmp/r",
            revset: "@",
            filePath: "x",
            diffService: service
        )
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if !state.diffCache.isLoading("x") { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(calls == 1)
    }

    @Test("refresh forceFull bypasses cache")
    func refreshForceFull() async throws {
        var calls = 0
        let service = JjDiffService(runner: { _, _, _, _ in
            calls += 1
            return JjProcessResult(status: 0, stdout: Data("diff --git a/x b/x\n".utf8), stderr: "")
        })
        let state = JjDiffViewerTabState(
            repoPath: "/tmp/r",
            revset: "@",
            filePath: "x",
            diffService: service
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        state.refresh(forceFull: true)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(calls >= 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter RoostTests.JjDiffViewerTabStateTests 2>&1 | tail -20
```

Expected: FAIL — `JjDiffViewerTabState` does not exist.

- [ ] **Step 3: Implement `JjDiffViewerTabState`**

Create `Muxy/Models/JjDiffViewerTabState.swift`:

```swift
import Foundation

@MainActor
@Observable
final class JjDiffViewerTabState: Identifiable {
    let id = UUID()
    let repoPath: String
    let revset: String
    let filePath: String
    let diffCache = DiffCache()
    var mode: VCSTabState.ViewMode = .unified

    var projectPath: String { repoPath }
    var displayTitle: String { (filePath as NSString).lastPathComponent }

    private let diffService: JjDiffService

    init(
        repoPath: String,
        revset: String,
        filePath: String,
        diffService: JjDiffService = JjDiffService()
    ) {
        self.repoPath = repoPath
        self.revset = revset
        self.filePath = filePath
        self.diffService = diffService
        load(forceFull: false)
    }

    func refresh(forceFull: Bool) {
        load(forceFull: forceFull)
    }

    private func load(forceFull: Bool) {
        if !forceFull, diffCache.hasDiff(for: filePath) {
            diffCache.touch(filePath)
            return
        }
        JjDiffLoader.load(
            JjDiffLoader.Request(
                repoPath: repoPath,
                revset: revset,
                filePath: filePath,
                forceFull: forceFull
            ),
            cache: diffCache,
            service: diffService
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter RoostTests.JjDiffViewerTabStateTests 2>&1 | tail -10
```

Expected: PASS (3 tests).

- [ ] **Step 5: Lint + build**

```bash
scripts/checks.sh --fix 2>&1 | tail -10
```

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(jj): add JjDiffViewerTabState owning its DiffCache"
```

---

## Task 4: `TerminalTab.Content.jjDiffViewer`

**Files:**
- Modify: `Muxy/Models/TerminalTab.swift`

- [ ] **Step 1: Add the case to the `Kind` enum**

In `Muxy/Models/TerminalTab.swift`, edit the `Kind` enum (lines 8-13):

```swift
    enum Kind: String, Codable {
        case terminal
        case vcs
        case editor
        case diffViewer
        case jjDiffViewer
    }
```

- [ ] **Step 2: Add the case to `Content`**

Edit the `Content` enum (lines 15-58). Add the case, kind, accessor, and projectPath:

```swift
    enum Content {
        case terminal(TerminalPaneState)
        case vcs(VCSTabState)
        case editor(EditorTabState)
        case diffViewer(DiffViewerTabState)
        case jjDiffViewer(JjDiffViewerTabState)

        var kind: Kind {
            switch self {
            case .terminal: .terminal
            case .vcs: .vcs
            case .editor: .editor
            case .diffViewer: .diffViewer
            case .jjDiffViewer: .jjDiffViewer
            }
        }

        var pane: TerminalPaneState? {
            guard case let .terminal(pane) = self else { return nil }
            return pane
        }

        var vcsState: VCSTabState? {
            guard case let .vcs(state) = self else { return nil }
            return state
        }

        var editorState: EditorTabState? {
            guard case let .editor(state) = self else { return nil }
            return state
        }

        var diffViewerState: DiffViewerTabState? {
            guard case let .diffViewer(state) = self else { return nil }
            return state
        }

        var jjDiffViewerState: JjDiffViewerTabState? {
            guard case let .jjDiffViewer(state) = self else { return nil }
            return state
        }

        var projectPath: String {
            switch self {
            case let .terminal(pane): pane.projectPath
            case let .vcs(state): state.projectPath
            case let .editor(state): state.projectPath
            case let .diffViewer(state): state.projectPath
            case let .jjDiffViewer(state): state.projectPath
            }
        }
    }
```

- [ ] **Step 3: Add the title case**

In the `var title: String` getter (lines 68-82), add the new case:

```swift
        switch content {
        case let .terminal(pane):
            return pane.title
        case .vcs:
            return "Git Diff"
        case let .editor(state):
            return state.displayTitle
        case let .diffViewer(state):
            return state.displayTitle
        case let .jjDiffViewer(state):
            return state.displayTitle
        }
```

- [ ] **Step 4: Add the convenience initializer**

After the existing `init(diffViewerState:)` (line 96):

```swift
    init(jjDiffViewerState: JjDiffViewerTabState) {
        content = .jjDiffViewer(jjDiffViewerState)
    }
```

- [ ] **Step 5: Add the restore stub**

In the snapshot-restore `init(restoring:)` switch (lines 107-138), add a fallback case that mirrors the `.diffViewer` case:

```swift
        case .jjDiffViewer:
            content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
```

- [ ] **Step 6: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: SUCCESS. The compiler will now flag `ContentHostLayer` for missing case coverage — that lands in Task 5.

- [ ] **Step 7: Lint**

```bash
scripts/checks.sh --fix 2>&1 | tail -10
```

- [ ] **Step 8: Commit**

```bash
jj commit -m "feat(tab): add jjDiffViewer case to TerminalTab.Content"
```

---

## Task 5+6: `ContentHostLayer` rendering + `JjDiffViewerPane`

**Files:**
- Modify: `Muxy/Views/Workspace/ContentHostLayer.swift`
- Create: `Muxy/Views/VCS/JjDiffViewerPane.swift`

These two land in one commit because Task 5 alone won't build (references `JjDiffViewerPane` before it exists).

- [ ] **Step 1: Add the entry case to `ContentHostLayer`**

In `Muxy/Views/Workspace/ContentHostLayer.swift`, extend the private `Entry` enum (lines 74-86):

```swift
    private enum Entry: Identifiable {
        case terminal(TerminalEntry)
        case editor(EditorEntry)
        case diff(DiffEntry)
        case jjDiff(JjDiffEntry)

        var id: UUID {
            switch self {
            case let .terminal(t): t.tabID
            case let .editor(e): e.tabID
            case let .diff(d): d.tabID
            case let .jjDiff(d): d.tabID
            }
        }
    }
```

- [ ] **Step 2: Add the entry struct**

After the existing `DiffEntry` struct (lines 108-115):

```swift
    private struct JjDiffEntry {
        let tabID: UUID
        let areaID: UUID
        let state: JjDiffViewerTabState
        let contentRect: CGRect
        let isVisible: Bool
        let isFocused: Bool
    }
```

- [ ] **Step 3: Map jj diff tabs into entries**

In `entries(frames:)` (lines 117-166), add a new case to the inner `switch tab.content`:

```swift
                case let .jjDiffViewer(state):
                    return [.jjDiff(JjDiffEntry(
                        tabID: tab.id,
                        areaID: area.id,
                        state: state,
                        contentRect: tabContentRect,
                        isVisible: isActiveTab,
                        isFocused: isFocused
                    ))]
```

- [ ] **Step 4: Render the new entry**

In `paneView(for:)` (lines 26-72), add a new case:

```swift
        case let .jjDiff(d):
            JjDiffViewerPane(
                state: d.state,
                focused: d.isFocused,
                onFocus: { dispatchFocus(areaID: d.areaID) }
            )
            .overlay {
                InactiveWindowClickView(action: { dispatchFocus(areaID: d.areaID) })
                    .accessibilityHidden(true)
            }
            .frame(width: d.contentRect.width, height: d.contentRect.height)
            .offset(x: d.contentRect.minX, y: d.contentRect.minY)
            .opacity(d.isVisible ? 1 : 0)
            .allowsHitTesting(d.isVisible)
            .zIndex(d.isVisible ? 1 : 0)
            .id(d.tabID)
```

- [ ] **Step 5: Create `JjDiffViewerPane`**

Create `Muxy/Views/VCS/JjDiffViewerPane.swift`:

```swift
import SwiftUI

struct JjDiffViewerPane: View {
    @Bindable var state: JjDiffViewerTabState
    let focused: Bool
    let onFocus: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            JjDiffViewerBreadcrumb(state: state)
            Rectangle().fill(MuxyTheme.border).frame(height: 1)
            ScrollView([.vertical]) {
                DiffBodyView(
                    isLoading: state.diffCache.isLoading(state.filePath),
                    error: state.diffCache.error(for: state.filePath),
                    diff: state.diffCache.diff(for: state.filePath),
                    filePath: state.filePath,
                    mode: state.mode,
                    onLoadFull: { state.refresh(forceFull: true) },
                    suppressLeadingTopBorder: true
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(MuxyTheme.bg)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onFocus() })
    }
}

private struct JjDiffViewerBreadcrumb: View {
    @Bindable var state: JjDiffViewerTabState

    private var loadedDiff: DiffCache.LoadedDiff? {
        state.diffCache.diff(for: state.filePath)
    }

    var body: some View {
        HStack(spacing: 6) {
            FileDiffIcon()
                .stroke(MuxyTheme.fgDim, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 11, height: 11)

            Text(state.filePath)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if let diff = loadedDiff {
                if diff.additions > 0 {
                    Text("+\(diff.additions)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MuxyTheme.diffAddFg)
                }
                if diff.deletions > 0 {
                    Text("-\(diff.deletions)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MuxyTheme.diffRemoveFg)
                }
            }

            Spacer()

            modeToggle

            IconButton(symbol: "arrow.clockwise", size: 11, accessibilityLabel: "Refresh Diff") {
                state.refresh(forceFull: false)
            }
            .help("Refresh")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(MuxyTheme.bg)
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeButton(.split, symbol: "rectangle.split.2x1", tooltip: "Side by side")
            modeButton(.unified, symbol: "rectangle", tooltip: "Inline")
        }
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(MuxyTheme.border, lineWidth: 1))
    }

    private func modeButton(_ mode: VCSTabState.ViewMode, symbol: String, tooltip: String) -> some View {
        let selected = state.mode == mode
        return Button {
            state.mode = mode
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? MuxyTheme.fg : MuxyTheme.fgMuted)
                .frame(width: 22, height: 20)
                .background(selected ? MuxyTheme.bg : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
```

- [ ] **Step 6: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: SUCCESS.

- [ ] **Step 7: Lint**

```bash
scripts/checks.sh --fix 2>&1 | tail -10
```

- [ ] **Step 8: Commit**

```bash
jj commit -m "feat(jj): render jj diff tabs via JjDiffViewerPane reusing DiffBodyView"
```

---

## Task 7: TabReducer + TabArea + Action

**Files:**
- Modify: `Muxy/Models/AppState.swift`
- Modify: `Muxy/Models/WorkspaceReducer/TabReducer.swift`
- Modify: `Muxy/Models/TabArea.swift`

- [ ] **Step 1: Add `JjDiffViewerRequest` and the action case**

In `Muxy/Models/AppState.swift`, near the existing `DiffViewerRequest` (line 30) and the action enum cases (line 59), add:

```swift
    struct JjDiffViewerRequest {
        let repoPath: String
        let revset: String
        let filePath: String
    }
```

And in the action enum (next to `case createDiffViewerTab` at line 59):

```swift
        case createJjDiffViewerTab(projectID: UUID, areaID: UUID?, request: JjDiffViewerRequest)
```

- [ ] **Step 2: Wire the dispatch case**

In the same file, find the dispatch switch statement (search for `case .createDiffViewerTab`). Add right after it:

```swift
        case let .createJjDiffViewerTab(projectID, areaID, request):
            TabReducer.createJjDiffViewerTab(
                projectID: projectID,
                areaID: areaID,
                request: request,
                state: &workspaceState
            )
```

- [ ] **Step 3: Add the reducer method**

In `Muxy/Models/WorkspaceReducer/TabReducer.swift`, after `createDiffViewerTab` (line 95-110), add:

```swift
    static func createJjDiffViewerTab(
        projectID: UUID,
        areaID: UUID?,
        request: AppState.JjDiffViewerRequest,
        state: inout WorkspaceState
    ) {
        guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
              let area = WorkspaceReducerShared.resolveArea(key: key, areaID: areaID, state: state)
        else { return }
        FocusReducer.focusArea(area.id, key: key, state: &state)
        area.createJjDiffViewerTab(
            repoPath: request.repoPath,
            revset: request.revset,
            filePath: request.filePath
        )
    }
```

- [ ] **Step 4: Add the TabArea factory**

In `Muxy/Models/TabArea.swift`, after `createDiffViewerTab` (line 118-131), add:

```swift
    func createJjDiffViewerTab(repoPath: String, revset: String, filePath: String) {
        if let existing = tabs.first(where: { tab in
            guard let diff = tab.content.jjDiffViewerState else { return false }
            return diff.repoPath == repoPath
                && diff.revset == revset
                && diff.filePath == filePath
        }) {
            selectTab(existing.id)
            return
        }
        insertTab(TerminalTab(jjDiffViewerState: JjDiffViewerTabState(
            repoPath: repoPath,
            revset: revset,
            filePath: filePath
        )))
    }
```

- [ ] **Step 5: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: SUCCESS.

- [ ] **Step 6: Lint**

```bash
scripts/checks.sh --fix 2>&1 | tail -10
```

- [ ] **Step 7: Commit**

```bash
jj commit -m "feat(workspace): wire createJjDiffViewerTab through reducer + TabArea"
```

---

## Task 8: `AppState.openJjDiffViewer`

**Files:**
- Modify: `Muxy/Models/AppState.swift`

- [ ] **Step 1: Add the method**

In `Muxy/Models/AppState.swift`, after `openDiffViewer` (line 665-680):

```swift
    func openJjDiffViewer(repoPath: String, revset: String, filePath: String, projectID: UUID) {
        for area in allAreas(for: projectID) {
            if let tab = area.tabs.first(where: { tab in
                guard let diff = tab.content.jjDiffViewerState else { return false }
                return diff.repoPath == repoPath
                    && diff.revset == revset
                    && diff.filePath == filePath
            }) {
                dispatch(.selectTab(projectID: projectID, areaID: area.id, tabID: tab.id))
                return
            }
        }
        dispatch(.createJjDiffViewerTab(
            projectID: projectID,
            areaID: nil,
            request: JjDiffViewerRequest(repoPath: repoPath, revset: revset, filePath: filePath)
        ))
    }
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: SUCCESS.

- [ ] **Step 3: Lint**

```bash
scripts/checks.sh --fix 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(app): add openJjDiffViewer with (repoPath, revset, filePath) dedupe"
```

---

## Task 9: `JjFileRow`

**Files:**
- Create: `Muxy/Views/VCS/JjFileRow.swift`

- [ ] **Step 1: Implement the row**

Create `Muxy/Views/VCS/JjFileRow.swift`:

```swift
import MuxyShared
import SwiftUI

struct JjFileRow: View {
    let entry: JjStatusEntry
    let onOpenInEditor: () -> Void
    let onOpenDiff: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.change.rawValue)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(statusColor)
                .frame(width: 12)

            Text(entry.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MuxyTheme.fg)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hovered {
                actionButtons
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .contentShape(Rectangle())
        .background(hovered ? MuxyTheme.surface : Color.clear)
        .onHover { hovered = $0 }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "doc.text", size: 11, accessibilityLabel: "Open in Editor", action: onOpenInEditor)
                .help("Open in Editor")
            IconButton(symbol: "rectangle.split.2x1", size: 11, accessibilityLabel: "Open Diff in New Tab", action: onOpenDiff)
                .help("Open Diff in New Tab")
        }
    }

    private var statusColor: Color {
        switch entry.change {
        case .added,
             .copied: MuxyTheme.diffAddFg
        case .deleted: MuxyTheme.diffRemoveFg
        case .modified,
             .renamed: MuxyTheme.fgMuted
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: SUCCESS.

- [ ] **Step 3: Lint**

```bash
scripts/checks.sh --fix 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(jj): add JjFileRow with hover toolbar (editor + diff)"
```

---

## Task 10: Wire `JjPanelView` to `JjFileRow`

**Files:**
- Modify: `Muxy/Views/VCS/JjPanelView.swift`

- [ ] **Step 1: Add `onOpenDiff` parameter**

In `JjPanelView.swift` (lines 6-43), add the parameter and forward it through the initializer:

```swift
struct JjPanelView: View {
    @Bindable var state: JjPanelState
    let onOpenFile: (String) -> Void
    let onOpenDiff: (String) -> Void
    // ... existing @State declarations stay ...

    init(
        state: JjPanelState,
        onOpenFile: @escaping (String) -> Void = { _ in },
        onOpenDiff: @escaping (String) -> Void = { _ in }
    ) {
        self.state = state
        self.onOpenFile = onOpenFile
        self.onOpenDiff = onOpenDiff
    }
```

- [ ] **Step 2: Replace `fileListContent` body**

In `JjPanelView.swift` (lines 470-495), replace the body of `fileListContent(entries:)` with:

```swift
    private func fileListContent(entries: [JjStatusEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if entries.isEmpty {
                Text("No working copy changes")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgDim)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries, id: \.path) { entry in
                        JjFileRow(
                            entry: entry,
                            onOpenInEditor: { onOpenFile(entry.path) },
                            onOpenDiff: { onOpenDiff(entry.path) }
                        )
                    }
                }
            }
        }
    }
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: SUCCESS.

- [ ] **Step 4: Lint**

```bash
scripts/checks.sh --fix 2>&1 | tail -10
```

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): use JjFileRow inside JjPanelView; expose onOpenDiff"
```

---

## Task 11: Wire `VCSTabView` to `openJjDiffViewer`

**Files:**
- Modify: `Muxy/Views/VCS/VCSTabView.swift`

- [ ] **Step 1: Pass `onOpenDiff` into `JjPanelView`**

In `VCSTabView.swift` (lines 115-124), update `jjContent`:

```swift
    @ViewBuilder
    private var jjContent: some View {
        if let jjState = state.jjState {
            JjPanelView(
                state: jjState,
                onOpenFile: { path in openFileInEditor(path) },
                onOpenDiff: { path in openJjDiffInTab(path, repoPath: jjState.repoPath) }
            )
        } else {
            jjPlaceholder
        }
    }
```

- [ ] **Step 2: Add the helper**

After `openDiffInTab` (line 717-720) in `VCSTabView.swift`:

```swift
    private func openJjDiffInTab(_ relativePath: String, repoPath: String) {
        guard let projectID = appState.activeProjectID else { return }
        appState.openJjDiffViewer(
            repoPath: repoPath,
            revset: "@",
            filePath: relativePath,
            projectID: projectID
        )
    }
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: SUCCESS.

- [ ] **Step 4: Run the full test suite**

```bash
swift test 2>&1 | tail -30
```

Expected: ALL TESTS PASS, including the three new test files.

- [ ] **Step 5: Lint with strict mode**

```bash
scripts/checks.sh 2>&1 | tail -10
```

Expected: SUCCESS.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(vcs): jj file rows open diff tab via openJjDiffViewer"
```

---

## Task 12: Manual smoke test (user step)

**Files:**
- None — runtime check only.

This is performed by the human after all subagent tasks complete.

- [ ] **Step 1: Build and run**

```bash
swift build 2>&1 | tail -5
swift run Roost
```

- [ ] **Step 2: In a jj-backed project**

  1. Open a project that uses jj (working tree must have at least one modified file).
  2. Open the source-control panel.
  3. Hover a file row → confirm the two icons (`doc.text`, `rectangle.split.2x1`) appear on the right.
  4. Click the diff icon → confirm a new tab opens with breadcrumb `<path>` and a populated unified diff.
  5. Toggle Split / Unified in the breadcrumb → confirm both render.
  6. Click Refresh in the breadcrumb → diff reloads.
  7. Click the editor icon → confirm the file opens in the editor (existing flow).
  8. Open the same file's diff a second time → confirm the existing tab is selected, no duplicate.

- [ ] **Step 3: Take screenshots / recording for the PR**

Per `CLAUDE.md`: "Upload screenshots or recordings for PRs that change UI."

---

## Self-review checklist (run before declaring done)

- [ ] All three new test files pass with `swift test`.
- [ ] `scripts/checks.sh` (no `--fix`) is green.
- [ ] `jj log` shows ~10 small commits, each scoped to one task.
- [ ] Hover toolbar icons appear only on hover (mirrors Git `FileRow` behavior).
- [ ] Tab dedupe works for `(repoPath, revset, filePath)`.
- [ ] No changes to `DiffBodyView` / `UnifiedDiffView` / `SplitDiffView` / `DiffCache` / `GitDiffParser` / `DiffDisplayRow`.
- [ ] No git-only concepts (`isStaged`, `pinnedPaths`, stage/unstage actions) leaked into the jj path.
- [ ] `TerminalTab` snapshot/restore for `.jjDiffViewer` falls back to a placeholder terminal — same asymmetry as `.diffViewer`.
