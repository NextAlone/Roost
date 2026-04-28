# Phase 5c — jj Panel: Mutating Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Add the 7 jj change-mutating actions (describe, new, commit, squash, abandon, duplicate, backout) to the panel. Each action runs serialized through `JjProcessQueue.shared` and triggers a state refresh on success.

**Architecture:** New `JjMutationService` (struct, mirroring `JjBookmarkService`) with 7 methods, each calling `runMutating(...)`. UI: action bar above the change card with buttons. Two sheets for text input (describe-message, commit-message). After each successful mutation, call `state.refresh()` to reload the panel.

**Tech Stack:** Swift 6, SwiftUI, swift-testing, existing `JjProcessQueue`, `JjRunFn`, `JjProcessError` infrastructure.

**Locked decisions:**
- Each mutation is a thin wrapper over a single `jj <subcmd>` invocation. No batching.
- All mutations use `snapshot: .allow` (default jj behavior — they intend to snapshot).
- Default revsets where required: `abandon` / `duplicate` / `backout` operate on `@` by default. `squash` collapses `@` into `@-`. `new` creates a new change on `@`. UI shows a single "Run" button per action — no per-action revset picker in 5c (Phase 5+ later if needed).
- `describe` and `commit` open sheets for message input. `commit` extracts the working-copy change as a new immutable commit and creates a fresh working-copy change; jj's exact semantics are preserved (no special -m logic beyond passing the message string).
- Action bar position: top of the panel, above the change card.

**Out of scope:**
- Bookmark CRUD (Phase 5d).
- Per-action revset pickers / advanced flags.
- Squash with arbitrary source/dest selection (sticks to `@` → `@-`).
- Operation log / undo (later).
- Confirmation dialogs (rely on jj's own safety; abandon is reversible via `jj op restore`).

---

## File Structure

**Create:**
- `Muxy/Services/Jj/JjMutationService.swift`
- `Muxy/Views/VCS/JjActionBar.swift`
- `Muxy/Views/VCS/JjMessageSheet.swift`
- `Tests/MuxyTests/Services/Jj/JjMutationServiceTests.swift`

**Modify:**
- `Muxy/Views/VCS/JjPanelView.swift` — add `JjActionBar` above the change card; host the message sheet

---

## Task 1: JjMutationService

**Files:**
- Create: `Muxy/Services/Jj/JjMutationService.swift`
- Test: `Tests/MuxyTests/Services/Jj/JjMutationServiceTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/MuxyTests/Services/Jj/JjMutationServiceTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("JjMutationService")
struct JjMutationServiceTests {
    private final class CommandRecorder: @unchecked Sendable {
        var commands: [[String]] = []
        let lock = NSLock()
        func record(_ cmd: [String]) {
            lock.lock(); defer { lock.unlock() }
            commands.append(cmd)
        }
    }

    @Test("describe sends jj describe -m <message>")
    func describe() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.describe(repoPath: "/tmp/wt", message: "hello world")
        #expect(recorder.commands == [["describe", "-m", "hello world"]])
    }

    @Test("new sends jj new")
    func newChange() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.newChange(repoPath: "/tmp/wt")
        #expect(recorder.commands == [["new"]])
    }

    @Test("commit sends jj commit -m <message>")
    func commitChange() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.commit(repoPath: "/tmp/wt", message: "feat: x")
        #expect(recorder.commands == [["commit", "-m", "feat: x"]])
    }

    @Test("squash sends jj squash")
    func squash() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.squash(repoPath: "/tmp/wt")
        #expect(recorder.commands == [["squash"]])
    }

    @Test("abandon sends jj abandon")
    func abandon() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.abandon(repoPath: "/tmp/wt")
        #expect(recorder.commands == [["abandon"]])
    }

    @Test("duplicate sends jj duplicate")
    func duplicate() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.duplicate(repoPath: "/tmp/wt")
        #expect(recorder.commands == [["duplicate"]])
    }

    @Test("backout sends jj backout -r @")
    func backout() async throws {
        let recorder = CommandRecorder()
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, cmd, _, _ in
            recorder.record(cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        })
        try await service.backout(repoPath: "/tmp/wt")
        #expect(recorder.commands == [["backout", "-r", "@"]])
    }

    @Test("non-zero exit throws")
    func nonZeroExit() async {
        let service = JjMutationService(queue: JjProcessQueue.shared, runner: { _, _, _, _ in
            JjProcessResult(status: 1, stdout: Data(), stderr: "boom")
        })
        await #expect(throws: (any Error).self) {
            try await service.describe(repoPath: "/tmp/wt", message: "x")
        }
    }
}
```

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter JjMutationServiceTests
```

- [ ] **Step 3: Implement**

Create `Muxy/Services/Jj/JjMutationService.swift`:

```swift
import Foundation
import MuxyShared

struct JjMutationService: Sendable {
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

    func describe(repoPath: String, message: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["describe", "-m", message])
    }

    func newChange(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["new"])
    }

    func commit(repoPath: String, message: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["commit", "-m", message])
    }

    func squash(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["squash"])
    }

    func abandon(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["abandon"])
    }

    func duplicate(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["duplicate"])
    }

    func backout(repoPath: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["backout", "-r", "@"])
    }

    private func runMutating(repoPath: String, command: [String]) async throws {
        let runner = self.runner
        try await queue.run(repoPath: repoPath, isMutating: true) {
            let result = try await runner(repoPath, command, .allow, nil)
            if result.status != 0 {
                throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
            }
        }
    }
}
```

The runMutating helper mirrors `JjBookmarkService.runMutating` exactly.

- [ ] **Step 4: Run targeted + full**

```bash
swift test --filter JjMutationServiceTests
swift test 2>&1 | tail -3
```

Expected: 8 new tests pass; total all green.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): JjMutationService for describe/new/commit/squash/abandon/duplicate/backout"
```

---

## Task 2: JjMessageSheet (text input)

**Files:**
- Create: `Muxy/Views/VCS/JjMessageSheet.swift`

- [ ] **Step 1: Implement**

Create `Muxy/Views/VCS/JjMessageSheet.swift`:

```swift
import SwiftUI

struct JjMessageSheet: View {
    let title: String
    let confirmLabel: String
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var message: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))

            TextEditor(text: $message)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(MuxyTheme.border, lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmLabel) {
                    onConfirm(message.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 460)
    }
}
```

If `MuxyTheme.border` is not the right color name (sometimes it's `borderColor` or similar), grep `Muxy/Theme/MuxyTheme.swift` for the available `border`-like static and use that.

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected SUCCESS.

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(jj): JjMessageSheet for describe/commit message input"
```

---

## Task 3: JjActionBar

**Files:**
- Create: `Muxy/Views/VCS/JjActionBar.swift`

- [ ] **Step 1: Implement**

Create `Muxy/Views/VCS/JjActionBar.swift`:

```swift
import MuxyShared
import SwiftUI

struct JjActionBar: View {
    let onDescribe: () -> Void
    let onNew: () -> Void
    let onCommit: () -> Void
    let onSquash: () -> Void
    let onAbandon: () -> Void
    let onDuplicate: () -> Void
    let onBackout: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            actionButton(systemImage: "pencil", label: "Describe", action: onDescribe)
            actionButton(systemImage: "plus.circle", label: "New", action: onNew)
            actionButton(systemImage: "checkmark.circle", label: "Commit", action: onCommit)
            actionButton(systemImage: "arrow.down.to.line", label: "Squash", action: onSquash)
            Divider().frame(height: 16)
            actionButton(systemImage: "trash", label: "Abandon", action: onAbandon)
            actionButton(systemImage: "doc.on.doc", label: "Duplicate", action: onDuplicate)
            actionButton(systemImage: "arrow.uturn.backward", label: "Backout", action: onBackout)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    private func actionButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        }
        .buttonStyle(.borderless)
        .help(label)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(jj): JjActionBar with 7 mutation buttons"
```

---

## Task 4: Wire actions into JjPanelView

**Files:**
- Modify: `Muxy/Views/VCS/JjPanelView.swift`

This task adds:
- `JjMutationService` instance (lazy / in-init).
- `@State private var showDescribeSheet`, `showCommitSheet`, `actionError` for error display.
- `JjActionBar` rendered above the changeCard.
- `.sheet(...)` for message input.
- `runMutation { ... }` helper that calls a service method, refreshes state, and surfaces errors.

- [ ] **Step 1: Read the file**

```bash
cat Muxy/Views/VCS/JjPanelView.swift
```

- [ ] **Step 2: Add the mutation infrastructure**

Replace `JjPanelView` with this version (keeping all existing helpers — only the body, the new state/services, and the action helpers change):

Add at top of struct, after `state: JjPanelState`:

```swift
    @State private var showDescribeSheet = false
    @State private var showCommitSheet = false
    @State private var actionError: String?

    private let mutator = JjMutationService(queue: JjProcessQueue.shared)
```

Modify the body. After `header` and before the `if let snapshot` branch, add:

```swift
            actionBar
            if let actionError {
                Text(actionError)
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.diffRemoveFg)
                    .padding(.horizontal, 4)
            }
```

Add the action bar helper near the bottom:

```swift
    private var actionBar: some View {
        JjActionBar(
            onDescribe: { showDescribeSheet = true },
            onNew: { runMutation { try await mutator.newChange(repoPath: state.repoPath) } },
            onCommit: { showCommitSheet = true },
            onSquash: { runMutation { try await mutator.squash(repoPath: state.repoPath) } },
            onAbandon: { runMutation { try await mutator.abandon(repoPath: state.repoPath) } },
            onDuplicate: { runMutation { try await mutator.duplicate(repoPath: state.repoPath) } },
            onBackout: { runMutation { try await mutator.backout(repoPath: state.repoPath) } }
        )
    }

    private func runMutation(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                actionError = nil
                await state.refresh()
            } catch {
                actionError = String(describing: error)
            }
        }
    }
```

Add the sheets at the end of body (chained on the outer VStack's modifiers):

```swift
        .sheet(isPresented: $showDescribeSheet) {
            JjMessageSheet(
                title: "Describe Change",
                confirmLabel: "Save",
                onConfirm: { message in
                    showDescribeSheet = false
                    runMutation { try await mutator.describe(repoPath: state.repoPath, message: message) }
                },
                onCancel: { showDescribeSheet = false }
            )
        }
        .sheet(isPresented: $showCommitSheet) {
            JjMessageSheet(
                title: "Commit Working Copy",
                confirmLabel: "Commit",
                onConfirm: { message in
                    showCommitSheet = false
                    runMutation { try await mutator.commit(repoPath: state.repoPath, message: message) }
                },
                onCancel: { showCommitSheet = false }
            )
        }
```

- [ ] **Step 3: Build + test**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -3
```

Expected SUCCESS, all green.

Manual smoke (optional but recommended): launch Roost on a jj-tracked repo, click "Describe", enter a message, hit Save — the change card should update with the new description.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(jj): wire mutation action bar + describe/commit sheets into JjPanelView"
```

---

## Task 5: Migration plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append after Phase 5b status block**

```markdown
**Status (2026-04-28): Phase 5c (mutating actions) landed.**

- `JjMutationService` exposes 7 mutations (describe, new, commit, squash, abandon, duplicate, backout) wrapping `jj <subcmd>` calls; all serialize through `JjProcessQueue.shared`.
- `JjActionBar` renders all 7 actions as a button bar above the change card.
- `JjMessageSheet` collects message input for describe + commit.
- After each successful mutation, `state.refresh()` reloads the panel.
- Errors surface inline below the action bar.
- Defaults: backout/abandon/duplicate operate on `@`; squash collapses `@` into `@-`. No per-action revset picker (deferred).
- Bookmark CRUD (5d) → upcoming.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(plan): mark Phase 5c (mutating actions) landed"
```

---

## Self-Review Checklist

- [ ] All 7 mutations have unit tests verifying the exact `jj` subcommand emitted.
- [ ] Sheets disable confirm button when message is empty/whitespace.
- [ ] `state.refresh()` runs after every successful mutation.
- [ ] No comments added.
- [ ] All builds + tests green.
