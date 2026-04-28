# Phase 4c.5 — Session Lifecycle Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Track each session's process lifecycle state (`running` / `exited`) and surface it as a colored dot on the sidebar `SessionRow`. Agent panes stop auto-closing on process exit — the pane stays visible with an "exited" badge so users can inspect command output or restart.

**Architecture:** Add `SessionLifecycleState` enum in MuxyShared. `TerminalPaneState.lastState` becomes a published mutable property (default `.running`). `TabAreaView`'s existing `onProcessExit` closure is the single hook — it now (a) sets `pane.lastState = .exited`, then (b) only closes the tab when `agentKind == .terminal`. `SessionRow` renders a small dot using `lastState`. Snapshot persistence stays consistent — no schema change needed because lifecycle is volatile (resets to `.running` on restart since the process is gone).

**Tech Stack:** Swift 6, SwiftUI, swift-testing.

**Locked decisions:**
- States this phase: `running`, `exited`. (`idle` and `errored` deferred — no clean signal.)
- Volatile state — not persisted to snapshot. Restart = all sessions back to `.running`. (Reasoning: by app restart the underlying process is gone; persisting `.exited` means showing stale state. We could initialize as `.exited` after restore but for simplicity, default `.running` and let the user notice when they interact.)
- Agent panes (`agentKind != .terminal`) NO LONGER auto-close on process exit. Pane persists with `.exited` badge. User closes the tab manually (existing close button).
- Non-agent panes (`.terminal`) keep current auto-close behavior.
- Badge palette: `running` = no badge (default state, would clutter UI); `exited` = `MuxyTheme.fgDim` dot.

**Out of scope:**
- `idle` detection (would need command-finished signal + heartbeat).
- `errored` distinction (Ghostty's CHILD_EXITED doesn't carry exit code per current adapter wiring).
- Restart action (Phase 5+ later).
- Snapshot persistence of lifecycle state.

---

## File Structure

**Create:**
- `MuxyShared/Agent/SessionLifecycleState.swift`
- `Tests/MuxyTests/Agent/SessionLifecycleStateTests.swift`

**Modify:**
- `Muxy/Models/TerminalPaneState.swift` — add `var lastState: SessionLifecycleState = .running`
- `Muxy/Views/Workspace/TabAreaView.swift` — `onProcessExit` closure now updates state and gates close by `agentKind`
- `Muxy/Views/Sidebar/SessionRow.swift` — render badge dot

---

## Task 1: SessionLifecycleState enum

**Files:**
- Create: `MuxyShared/Agent/SessionLifecycleState.swift`
- Test: `Tests/MuxyTests/Agent/SessionLifecycleStateTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import Foundation
import MuxyShared
import Testing

@Suite("SessionLifecycleState")
struct SessionLifecycleStateTests {
    @Test("Codable round-trips all cases")
    func codableRoundTrip() throws {
        let original = SessionLifecycleState.allCases
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([SessionLifecycleState].self, from: data)
        #expect(decoded == original)
    }

    @Test("raw values are stable")
    func rawValues() {
        #expect(SessionLifecycleState.running.rawValue == "running")
        #expect(SessionLifecycleState.exited.rawValue == "exited")
    }
}
```

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter SessionLifecycleStateTests
```

- [ ] **Step 3: Implement**

Create `MuxyShared/Agent/SessionLifecycleState.swift`:

```swift
import Foundation

public enum SessionLifecycleState: String, Sendable, Codable, Hashable, CaseIterable {
    case running
    case exited
}
```

- [ ] **Step 4: Run targeted + full**

```bash
swift test --filter SessionLifecycleStateTests
swift test 2>&1 | tail -3
```

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(agent): SessionLifecycleState (running/exited) enum"
```

---

## Task 2: TerminalPaneState.lastState

**Files:**
- Modify: `Muxy/Models/TerminalPaneState.swift`

- [ ] **Step 1: Read current contents**

```bash
cat Muxy/Models/TerminalPaneState.swift
```

- [ ] **Step 2: Add the property**

In `TerminalPaneState`, add (after `let createdAt: Date`, before `let searchState`):

```swift
    var lastState: SessionLifecycleState = .running
```

This is `var` (mutable) and not in `init` — defaults to `.running` on construction. No snapshot persistence (volatile state, see plan locked decisions).

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```

Expected SUCCESS — purely additive.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(terminal): TerminalPaneState.lastState defaults to .running"
```

---

## Task 3: TabAreaView gates close by agentKind + updates lifecycle

**Files:**
- Modify: `Muxy/Views/Workspace/TabAreaView.swift`

- [ ] **Step 1: Inspect current onProcessExit**

```bash
grep -n "onProcessExit:" Muxy/Views/Workspace/TabAreaView.swift
```

You should see (around line 65) a closure `onProcessExit: { onForceCloseTab(tab.id) }`. We replace this body to:

1. Set `tab.content.pane?.lastState = .exited`.
2. Only close the tab when `pane.agentKind == .terminal` (otherwise leave the pane visible with the exited badge).

- [ ] **Step 2: Replace the closure body**

Find the existing `onProcessExit:` line and replace its closure with:

```swift
                        onProcessExit: {
                            if let pane = tab.content.pane {
                                pane.lastState = .exited
                                if pane.agentKind == .terminal {
                                    onForceCloseTab(tab.id)
                                }
                            } else {
                                onForceCloseTab(tab.id)
                            }
                        },
```

The fallback `else { onForceCloseTab(tab.id) }` covers the unlikely case of non-pane content (vcs/editor/diffViewer) — should never reach here in practice but keeps the contract safe.

- [ ] **Step 3: Build + test**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -3
```

Expected SUCCESS, all green.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(terminal): mark pane .exited on process exit; agents stay open"
```

---

## Task 4: SessionRow lifecycle badge

**Files:**
- Modify: `Muxy/Views/Sidebar/SessionRow.swift`

- [ ] **Step 1: Read current SessionRow**

```bash
cat Muxy/Views/Sidebar/SessionRow.swift
```

You should see the existing structure — agentKind icon + title + selection.

- [ ] **Step 2: Add a lifecycle dot**

Modify the `body` to insert a lifecycle dot after the title:

```swift
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: agentKind.iconSystemName)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? MuxyTheme.accent : MuxyTheme.fgDim)
                    .frame(width: 12)

                Text(tab.title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? MuxyTheme.fg : MuxyTheme.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                lifecycleDot

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(agentKind.displayName): \(tab.title)")
    }
```

Add the helper inside the struct:

```swift
    @ViewBuilder
    private var lifecycleDot: some View {
        switch tab.content.pane?.lastState ?? .running {
        case .running:
            EmptyView()
        case .exited:
            Circle()
                .fill(MuxyTheme.fgDim)
                .frame(width: 5, height: 5)
                .accessibilityLabel("Exited")
        }
    }
```

`tab.content.pane?.lastState` may be nil if content isn't `.terminal` — but `SessionRow` is only used inside the session list which is built from `appState.allTabs(forKey:)`. Tabs without a pane (vcs/editor/diff) shouldn't be in that list normally; default to `.running` (no badge) for safety.

- [ ] **Step 3: Build + test**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -3
```

Expected SUCCESS.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(sidebar): SessionRow lifecycle dot for exited sessions"
```

---

## Task 5: Migration plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append after the Phase 4c block**

In the Phase 4 section, after the Phase 4c status block:

```markdown
**Status (2026-04-28): Phase 4c.5 (session lifecycle badge) landed.**

- `SessionLifecycleState` enum (running / exited) lives in `MuxyShared/Agent/`.
- `TerminalPaneState.lastState: SessionLifecycleState` defaults to `.running`. Volatile — not persisted to snapshot (lifecycle resets on restart since the process is gone).
- `TabAreaView.onProcessExit` now sets `pane.lastState = .exited` and conditionally force-closes the tab — only for non-agent panes (`agentKind == .terminal`). Agent panes stay visible with the exited badge so users can inspect output.
- `SessionRow` renders a small grey dot for `.exited` sessions; no badge for `.running` (default state, avoids clutter).
- `idle` and `errored` states deferred — no clean signal from Ghostty's current action wiring.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(plan): mark Phase 4c.5 (session lifecycle) landed"
```

---

## Self-Review Checklist

- [ ] No comments added.
- [ ] Build + test green.
- [ ] No persistence schema change.
- [ ] Non-agent panes' auto-close behavior unchanged.
- [ ] Agent panes (.claudeCode, .codex, .geminiCli, .openCode) don't auto-close on exit.
