# Phase 5d — jj Panel: Bookmark CRUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Wire the existing `JjBookmarkService.create / setTarget / forget` methods into UI affordances within the bookmark list area of `JjPanelView`. Users can create a new bookmark (defaults to current change), retarget an existing bookmark to current change, or delete a bookmark.

**Architecture:** Sheet-based: `JjBookmarkCreateSheet` for name input. Per-row context menu on bookmarks for retarget / delete. After each successful action, refresh panel state.

**Tech Stack:** Swift 6, SwiftUI, swift-testing, existing `JjBookmarkService`.

**Locked decisions:**
- Bookmark create dialog accepts a name; defaults the target to `@` (current change).
- Retarget moves an existing bookmark to `@` — single-click action with no extra prompt.
- Delete uses `jj bookmark forget` (matches the existing service method, which already wraps `forget`).
- Errors surface in the same inline banner Phase 5c added.
- No batch operations.

**Out of scope:**
- Bookmark create-with-arbitrary-revset (5d uses `@` only).
- Push/pull bookmark to remote (Phase 5+ later, possibly Phase 6/7).
- Rename bookmark (= forget + create with new name; deferred).
- Conflict detection on bookmark moves.

---

## File Structure

**Create:**
- `Muxy/Views/VCS/JjBookmarkCreateSheet.swift`

**Modify:**
- `Muxy/Views/VCS/JjPanelView.swift` — add new-bookmark button + per-row context menu wiring; thread mutator helpers through `runMutation`

---

## Task 1: JjBookmarkCreateSheet

**Files:**
- Create: `Muxy/Views/VCS/JjBookmarkCreateSheet.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct JjBookmarkCreateSheet: View {
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Bookmark")
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 11)).foregroundStyle(MuxyTheme.fgMuted)
                TextField("feature-x", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Target: current change (@)")
                .font(.system(size: 10))
                .foregroundStyle(MuxyTheme.fgDim)

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    onConfirm(name.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(jj): JjBookmarkCreateSheet for new bookmark name input"
```

---

## Task 2: Wire bookmark CRUD into JjPanelView

**Files:**
- Modify: `Muxy/Views/VCS/JjPanelView.swift`

- [ ] **Step 1: Inspect existing bookmarkList helper**

```bash
grep -n "private func bookmarkList\|let bookmarkService\|JjBookmarkService" Muxy/Views/VCS/JjPanelView.swift
```

You'll see `bookmarkList(bookmarks:)` from Phase 5b. Currently it renders a list of HStacks per bookmark — no actions. We add a context menu per-row plus a "+ New" button next to the section header.

- [ ] **Step 2: Add a bookmark service property**

Right after the existing `let mutator = JjMutationService(queue: JjProcessQueue.shared)` (added in Phase 5c), add:

```swift
    private let bookmarks = JjBookmarkService(queue: JjProcessQueue.shared)

    @State private var showCreateBookmarkSheet = false
```

- [ ] **Step 3: Modify bookmarkList helper**

Replace the existing `bookmarkList(bookmarks:)` method body with:

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
                Spacer()
                Button {
                    showCreateBookmarkSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("New bookmark")
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
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Move to current change") {
                            runMutation {
                                try await self.bookmarks.setTarget(
                                    repoPath: state.repoPath,
                                    name: bookmark.name,
                                    revset: "@"
                                )
                            }
                        }
                        Button("Delete", role: .destructive) {
                            runMutation {
                                try await self.bookmarks.forget(
                                    repoPath: state.repoPath,
                                    name: bookmark.name
                                )
                            }
                        }
                    }
                }
            }
        }
    }
```

The two key additions are:
- `+` button in the section header that toggles `showCreateBookmarkSheet`.
- `.contextMenu` on each bookmark row with "Move to current change" and "Delete" actions, both routed through the existing `runMutation { ... }` helper.

NOTE: `self.bookmarks` may shadow `bookmarks` parameter — use `self.bookmarks` explicitly to disambiguate the service vs the parameter.

- [ ] **Step 4: Add the create sheet modifier**

Where the existing `.sheet(isPresented: $showDescribeSheet)` and `.sheet(isPresented: $showCommitSheet)` live (chain on the outer VStack), append a third sheet:

```swift
        .sheet(isPresented: $showCreateBookmarkSheet) {
            JjBookmarkCreateSheet(
                onConfirm: { name in
                    showCreateBookmarkSheet = false
                    runMutation {
                        try await self.bookmarks.create(
                            repoPath: state.repoPath,
                            name: name,
                            revset: "@"
                        )
                    }
                },
                onCancel: { showCreateBookmarkSheet = false }
            )
        }
```

- [ ] **Step 5: Build + test**

```bash
swift build 2>&1 | tail -10
swift test 2>&1 | tail -3
```

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(jj): bookmark create + retarget + delete in JjPanelView"
```

---

## Task 3: Migration plan note + close-out

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append after Phase 5c status block**

```markdown
**Status (2026-04-28): Phase 5d (bookmark CRUD) landed.**

- "+" button in the bookmarks section header opens `JjBookmarkCreateSheet` to create a bookmark targeting `@`.
- Right-click context menu on each bookmark row: "Move to current change" and "Delete" actions.
- All actions route through the existing `runMutation` helper for serialized execution + error surfacing + state refresh.
- **Phase 5 complete.** Future enhancements: per-action revset pickers, push/pull, rename bookmark, conflict resolution UI, DAG view, op log / undo.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(plan): mark Phase 5d (bookmark CRUD) landed; Phase 5 complete"
```

---

## Self-Review Checklist

- [ ] All three bookmark operations (create / retarget / delete) call existing `JjBookmarkService` methods.
- [ ] No new mutating service code — purely UI wiring.
- [ ] `runMutation` helper from Phase 5c handles refresh + error consistently.
- [ ] No comments added.
- [ ] Build + test green.
