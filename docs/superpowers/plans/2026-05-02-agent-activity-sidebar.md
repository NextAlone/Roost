# Agent Activity Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show each coding agent's last known activity state in the sidebar, using provider hook events instead of terminal process lifecycle events.

**Architecture:** Keep `SessionLifecycleState` as the terminal process lifecycle (`running` / `exited`) and add a separate `AgentActivityState` for agent-level state. Provider hooks send activity-qualified socket types such as `codex_hook:needs_input`; the socket server parses the activity, updates the matching pane through `AppState`, and keeps the existing notification behavior. `SessionRow` renders a compact Superset-style status chip for non-terminal agent panes.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, existing Unix socket notification server, existing provider hook scripts, jj for VCS.

---

## Scope And Signal Boundaries

- Ghostty child-process events only drive `SessionLifecycleState.exited`.
- Agent hooks drive `AgentActivityState`.
- This plan does not claim full real-time inference of model thinking. It shows the last reliable event Roost receives:
  - `running`: default when an agent pane is created or restored.
  - `needsInput`: hook says the agent needs attention, permission, or user input.
  - `completed`: hook says the agent stopped or finished a turn.
  - `idle`: hook explicitly reports an idle session.
  - `exited`: terminal child process exited.
- Hostd SQLite schema is not changed in this pass. The sidebar reads live `TerminalPaneState`; future XPC hostd work can persist the same enum later.

## File Structure

- Create `MuxyShared/Agent/AgentActivityState.swift`
  - Shared enum and stable raw values.
  - Human-facing short labels for sidebar and accessibility.
- Modify `Muxy/Models/TerminalPaneState.swift`
  - Add `var activityState: AgentActivityState = .running`.
- Create `Muxy/Services/AgentActivity/AgentActivitySocketEvent.swift`
  - Pure parser for socket `type` values.
  - Strips activity suffixes while preserving provider source mapping.
- Modify `Muxy/Services/AIProviderIntegration.swift`
  - Make notification source lookup accept activity-qualified type strings.
- Modify `Muxy/Models/AppState.swift`
  - Add `updateAgentActivity(paneID:state:)`.
- Modify `Muxy/Services/NotificationSocketServer.swift`
  - Parse socket activity event and update pane state before inserting notification.
- Modify provider scripts:
  - `Muxy/Resources/scripts/muxy-claude-hook.sh`
  - `Muxy/Resources/scripts/muxy-codex-hook.sh`
  - `Muxy/Resources/scripts/muxy-cursor-hook.sh`
  - `Muxy/Resources/scripts/opencode-muxy-plugin.js`
- Create `Muxy/Views/Sidebar/AgentActivityBadge.swift`
  - Superset-style compact status chip.
- Modify `Muxy/Views/Sidebar/SessionRow.swift`
  - Render status chip for non-terminal agent panes.
- Update docs:
  - `docs/notification-setup.md`
  - `docs/roost-migration-plan.md`

---

## Task 1: Add AgentActivityState

**Files:**
- Create: `MuxyShared/Agent/AgentActivityState.swift`
- Modify: `Muxy/Models/TerminalPaneState.swift`
- Test: `Tests/MuxyTests/Agent/AgentActivityStateTests.swift`
- Test: `Tests/MuxyTests/Models/AgentTabCreationTests.swift`

- [ ] **Step 1: Write the failing enum test**

Create `Tests/MuxyTests/Agent/AgentActivityStateTests.swift`:

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
        #expect(AgentActivityState.needsInput.rawValue == "needsInput")
        #expect(AgentActivityState.idle.rawValue == "idle")
        #expect(AgentActivityState.completed.rawValue == "completed")
        #expect(AgentActivityState.exited.rawValue == "exited")
    }

    @Test("sidebar labels are compact")
    func sidebarLabels() {
        #expect(AgentActivityState.running.sidebarLabel == "RUN")
        #expect(AgentActivityState.needsInput.sidebarLabel == "WAIT")
        #expect(AgentActivityState.idle.sidebarLabel == "IDLE")
        #expect(AgentActivityState.completed.sidebarLabel == "DONE")
        #expect(AgentActivityState.exited.sidebarLabel == "EXIT")
    }
}
```

- [ ] **Step 2: Add the failing pane default assertion**

In `Tests/MuxyTests/Models/AgentTabCreationTests.swift`, add this assertion inside `claudeCase()`:

```swift
#expect(pane?.activityState == .running)
```

- [ ] **Step 3: Run tests and verify they fail**

Run:

```bash
swift test --filter AgentActivityStateTests
swift test --filter AgentTabCreationTests/claudeCase
```

Expected:

- `AgentActivityStateTests` fails with `cannot find 'AgentActivityState' in scope`.
- `AgentTabCreationTests/claudeCase` fails with `value of type 'TerminalPaneState' has no member 'activityState'`.

- [ ] **Step 4: Add the enum**

Create `MuxyShared/Agent/AgentActivityState.swift`:

```swift
import Foundation

public enum AgentActivityState: String, Sendable, Codable, Hashable, CaseIterable {
    case running
    case needsInput
    case idle
    case completed
    case exited

    public var sidebarLabel: String {
        switch self {
        case .running: "RUN"
        case .needsInput: "WAIT"
        case .idle: "IDLE"
        case .completed: "DONE"
        case .exited: "EXIT"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .running: "Running"
        case .needsInput: "Needs input"
        case .idle: "Idle"
        case .completed: "Completed"
        case .exited: "Exited"
        }
    }
}
```

- [ ] **Step 5: Add pane state**

Modify `Muxy/Models/TerminalPaneState.swift` near `lastState`:

```swift
var lastState: SessionLifecycleState = .running
var activityState: AgentActivityState = .running
```

- [ ] **Step 6: Run tests and verify they pass**

Run:

```bash
swift test --filter AgentActivityStateTests
swift test --filter AgentTabCreationTests/claudeCase
```

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```bash
jj st
jj commit -m "feat(agent): add activity state"
```

---

## Task 2: Parse Agent Activity From Socket Type

**Files:**
- Create: `Muxy/Services/AgentActivity/AgentActivitySocketEvent.swift`
- Test: `Tests/MuxyTests/Services/AgentActivitySocketEventTests.swift`

- [ ] **Step 1: Write the failing parser tests**

Create `Tests/MuxyTests/Services/AgentActivitySocketEventTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("AgentActivitySocketEvent")
struct AgentActivitySocketEventTests {
    @Test("parses needs input suffix")
    func needsInput() {
        let event = AgentActivitySocketEvent.parse(type: "codex_hook:needs_input")
        #expect(event.sourceType == "codex_hook")
        #expect(event.activityState == .needsInput)
    }

    @Test("parses completed suffix")
    func completed() {
        let event = AgentActivitySocketEvent.parse(type: "claude_hook:completed")
        #expect(event.sourceType == "claude_hook")
        #expect(event.activityState == .completed)
    }

    @Test("parses idle suffix")
    func idle() {
        let event = AgentActivitySocketEvent.parse(type: "opencode:idle")
        #expect(event.sourceType == "opencode")
        #expect(event.activityState == .idle)
    }

    @Test("legacy type keeps source and has no activity")
    func legacy() {
        let event = AgentActivitySocketEvent.parse(type: "cursor_hook")
        #expect(event.sourceType == "cursor_hook")
        #expect(event.activityState == nil)
    }

    @Test("unknown suffix keeps full type as source")
    func unknownSuffix() {
        let event = AgentActivitySocketEvent.parse(type: "custom:build_finished")
        #expect(event.sourceType == "custom:build_finished")
        #expect(event.activityState == nil)
    }
}
```

- [ ] **Step 2: Run the parser tests and verify they fail**

Run:

```bash
swift test --filter AgentActivitySocketEventTests
```

Expected: FAIL with `cannot find 'AgentActivitySocketEvent' in scope`.

- [ ] **Step 3: Add the parser**

Create `Muxy/Services/AgentActivity/AgentActivitySocketEvent.swift`:

```swift
import Foundation
import MuxyShared

struct AgentActivitySocketEvent: Equatable {
    let sourceType: String
    let activityState: AgentActivityState?

    static func parse(type rawType: String) -> AgentActivitySocketEvent {
        let trimmed = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorIndex = trimmed.lastIndex(of: ":") else {
            return AgentActivitySocketEvent(sourceType: trimmed, activityState: nil)
        }

        let source = String(trimmed[..<separatorIndex])
        let suffix = String(trimmed[trimmed.index(after: separatorIndex)...])
        guard !source.isEmpty, let state = activityState(from: suffix) else {
            return AgentActivitySocketEvent(sourceType: trimmed, activityState: nil)
        }
        return AgentActivitySocketEvent(sourceType: source, activityState: state)
    }

    private static func activityState(from suffix: String) -> AgentActivityState? {
        switch suffix {
        case "running":
            .running
        case "needs_input", "needsInput", "permission", "notification":
            .needsInput
        case "idle":
            .idle
        case "completed", "complete", "done", "stop", "stopped":
            .completed
        case "exited", "exit":
            .exited
        default:
            nil
        }
    }
}
```

- [ ] **Step 4: Run parser tests and verify they pass**

Run:

```bash
swift test --filter AgentActivitySocketEventTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
jj st
jj commit -m "feat(agent): parse activity socket events"
```

---

## Task 3: Update Live Pane Activity In AppState

**Files:**
- Modify: `Muxy/Models/AppState.swift`
- Test: `Tests/MuxyTests/Models/AppStateAgentActivityTests.swift`

- [ ] **Step 1: Write the failing AppState tests**

Create `Tests/MuxyTests/Models/AppStateAgentActivityTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("AppState agent activity")
struct AppStateAgentActivityTests {
    @Test("updates matching pane activity state")
    func updatesMatchingPane() {
        let appState = makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        let paneID = area.activeTab!.content.pane!.id
        appState.workspaceRoots[key] = .tabArea(area)

        let updated = appState.updateAgentActivity(paneID: paneID, state: .needsInput)

        #expect(updated == true)
        #expect(area.activeTab?.content.pane?.activityState == .needsInput)
    }

    @Test("returns false for missing pane")
    func missingPane() {
        let appState = makeAppState()
        let updated = appState.updateAgentActivity(paneID: UUID(), state: .completed)
        #expect(updated == false)
    }

    private func makeAppState() -> AppState {
        AppState(
            selectionStore: AgentActivitySelectionStoreStub(),
            terminalViews: AgentActivityTerminalViewRemovingStub(),
            workspacePersistence: AgentActivityWorkspacePersistenceStub()
        )
    }
}

@MainActor
private final class AgentActivitySelectionStoreStub: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_ id: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {}
}

@MainActor
private final class AgentActivityTerminalViewRemovingStub: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private final class AgentActivityWorkspacePersistenceStub: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {}
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter AppStateAgentActivityTests
```

Expected: FAIL with `value of type 'AppState' has no member 'updateAgentActivity'`.

- [ ] **Step 3: Add the update method**

Modify `Muxy/Models/AppState.swift` after `allTabs(forKey:)`:

```swift
@discardableResult
func updateAgentActivity(paneID: UUID, state: AgentActivityState) -> Bool {
    for root in workspaceRoots.values {
        for area in root.allAreas() {
            for tab in area.tabs {
                guard let pane = tab.content.pane, pane.id == paneID else { continue }
                pane.activityState = state
                return true
            }
        }
    }
    return false
}
```

- [ ] **Step 4: Run tests and verify they pass**

Run:

```bash
swift test --filter AppStateAgentActivityTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
jj st
jj commit -m "feat(agent): update pane activity state"
```

---

## Task 4: Wire Activity Events Through NotificationSocketServer

**Files:**
- Modify: `Muxy/Services/NotificationSocketServer.swift`
- Modify: `Muxy/Services/AIProviderIntegration.swift`
- Test: `Tests/MuxyTests/Services/AgentActivitySocketEventTests.swift`

- [ ] **Step 1: Add source canonicalization tests**

Append to `Tests/MuxyTests/Services/AgentActivitySocketEventTests.swift`:

```swift
@MainActor
@Test("activity suffix does not break provider source lookup")
func sourceLookupUsesBaseType() {
    let codex = AIProviderRegistry.shared.notificationSource(for: "codex_hook:needs_input")
    let claude = AIProviderRegistry.shared.notificationSource(for: "claude_hook:completed")
    #expect(codex == .aiProvider("codex"))
    #expect(claude == .aiProvider("claude"))
}
```

- [ ] **Step 2: Run tests and verify the new test fails**

Run:

```bash
swift test --filter AgentActivitySocketEventTests/sourceLookupUsesBaseType
```

Expected: FAIL because `notificationSource(for:)` currently compares the full type string.

- [ ] **Step 3: Canonicalize provider lookup**

Modify `Muxy/Services/AIProviderIntegration.swift` in `notificationSource(for:)`:

```swift
func notificationSource(for socketType: String) -> MuxyNotification.Source {
    let event = AgentActivitySocketEvent.parse(type: socketType)
    for provider in providers where provider.socketTypeKey == event.sourceType {
        return .aiProvider(provider.id)
    }
    return .socket
}
```

- [ ] **Step 4: Run source lookup test and verify it passes**

Run:

```bash
swift test --filter AgentActivitySocketEventTests/sourceLookupUsesBaseType
```

Expected: PASS.

- [ ] **Step 5: Wire updates in socket dispatch**

Modify `Muxy/Services/NotificationSocketServer.swift` inside `dispatchNotification(type:title:body:paneIDString:)`.

Replace:

```swift
let source = AIProviderRegistry.shared.notificationSource(for: type)
```

with:

```swift
let activityEvent = AgentActivitySocketEvent.parse(type: type)
let source = AIProviderRegistry.shared.notificationSource(for: activityEvent.sourceType)
```

In the pane-ID branch, before `NotificationStore.shared.add(...)`, insert:

```swift
if let state = activityEvent.activityState {
    appState.updateAgentActivity(paneID: paneID, state: state)
}
```

For the fallback branch, replace the local `context` binding:

```swift
let context = findFirstPaneContext(key: key, appState: appState)
```

with:

```swift
let fallback = findFirstPaneContext(key: key, appState: appState)
```

Then before `NotificationStore.shared.addWithContext(...)`, insert:

```swift
if let state = activityEvent.activityState {
    appState.updateAgentActivity(paneID: fallback.paneID, state: state)
}
```

And pass `fallback.context` to `addWithContext`.

- [ ] **Step 6: Add fallback context struct**

Modify `Muxy/Services/NotificationSocketServer.swift` by adding this private struct above `final class NotificationSocketServer`:

```swift
private struct PaneNotificationContext {
    let paneID: UUID
    let context: NavigationContext
}
```

Change `findFirstPaneContext(...)` return type:

```swift
) -> PaneNotificationContext? {
```

Inside the loop, change the `return NavigationContext(...)` to:

```swift
return PaneNotificationContext(
    paneID: pane.id,
    context: NavigationContext(
        projectID: key.projectID,
        worktreeID: key.worktreeID,
        worktreePath: path,
        areaID: area.id,
        tabID: tab.id
    )
)
```

- [ ] **Step 7: Run relevant tests**

Run:

```bash
swift test --filter AgentActivitySocketEventTests
swift test --filter AppStateAgentActivityTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

Run:

```bash
jj st
jj commit -m "feat(agent): route socket activity to panes"
```

---

## Task 5: Emit Activity Events From Provider Hooks

**Files:**
- Modify: `Muxy/Resources/scripts/muxy-claude-hook.sh`
- Modify: `Muxy/Resources/scripts/muxy-codex-hook.sh`
- Modify: `Muxy/Resources/scripts/muxy-cursor-hook.sh`
- Modify: `Muxy/Resources/scripts/opencode-muxy-plugin.js`
- Test: `Tests/MuxyTests/Services/AgentHookScriptTests.swift`

- [ ] **Step 1: Write resource-level script tests**

Create `Tests/MuxyTests/Services/AgentHookScriptTests.swift`:

```swift
import Foundation
import Testing

@Suite("Agent hook scripts")
struct AgentHookScriptTests {
    @Test("Claude hook emits activity-qualified socket types")
    func claudeHookTypes() throws {
        let script = try resourceText("Muxy/Resources/scripts/muxy-claude-hook.sh")
        #expect(script.contains("\"claude_hook:needs_input\""))
        #expect(script.contains("\"claude_hook:completed\""))
    }

    @Test("Codex hook emits activity-qualified socket types")
    func codexHookTypes() throws {
        let script = try resourceText("Muxy/Resources/scripts/muxy-codex-hook.sh")
        #expect(script.contains("\"codex_hook:needs_input\""))
        #expect(script.contains("\"codex_hook:completed\""))
    }

    @Test("Cursor hook emits activity-qualified socket types")
    func cursorHookTypes() throws {
        let script = try resourceText("Muxy/Resources/scripts/muxy-cursor-hook.sh")
        #expect(script.contains("\"cursor_hook:needs_input\""))
        #expect(script.contains("\"cursor_hook:completed\""))
    }

    @Test("OpenCode plugin emits idle activity")
    func openCodeIdleType() throws {
        let script = try resourceText("Muxy/Resources/scripts/opencode-muxy-plugin.js")
        #expect(script.contains("opencode:idle"))
    }

    private func resourceText(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run:

```bash
swift test --filter AgentHookScriptTests
```

Expected: FAIL because scripts still send legacy type strings.

- [ ] **Step 3: Update Claude hook**

Modify `Muxy/Resources/scripts/muxy-claude-hook.sh`:

```bash
case "$event" in
    notification)
        send_notification "claude_hook:needs_input" "Claude Code" "Needs attention"
        ;;
    stop)
        body=$(extract_last_message)
        send_notification "claude_hook:completed" "Claude Code" "$body"
        ;;
esac
```

- [ ] **Step 4: Update Codex hook**

Modify `Muxy/Resources/scripts/muxy-codex-hook.sh`:

```bash
case "$event" in
    notification)
        send_notification "codex_hook:needs_input" "Codex" "Needs attention"
        ;;
    stop)
        body=$(extract_last_message)
        send_notification "codex_hook:completed" "Codex" "$body"
        ;;
esac
```

- [ ] **Step 5: Update Cursor hook**

Modify `Muxy/Resources/scripts/muxy-cursor-hook.sh`:

```bash
case "$event" in
    PermissionRequest|permission)
        send_notification "cursor_hook:needs_input" "Cursor" "Needs attention"
        ;;
    Stop|stop)
        body=$(extract_last_message)
        send_notification "cursor_hook:completed" "Cursor" "$body"
        ;;
esac
```

- [ ] **Step 6: Update OpenCode plugin**

Modify `Muxy/Resources/scripts/opencode-muxy-plugin.js`:

```javascript
const payload = `opencode:idle|${paneID}|OpenCode|${body}`
```

- [ ] **Step 7: Run script tests and verify they pass**

Run:

```bash
swift test --filter AgentHookScriptTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

Run:

```bash
jj st
jj commit -m "feat(agent): emit activity from hooks"
```

---

## Task 6: Render Superset-Style Agent Status In Sidebar

**Files:**
- Create: `Muxy/Views/Sidebar/AgentActivityBadge.swift`
- Modify: `Muxy/Views/Sidebar/SessionRow.swift`
- Test: `Tests/MuxyTests/Agent/AgentActivityStateTests.swift`

- [ ] **Step 1: Add display metadata tests**

Append to `Tests/MuxyTests/Agent/AgentActivityStateTests.swift`:

```swift
@Test("accessibility labels are human readable")
func accessibilityLabels() {
    #expect(AgentActivityState.running.accessibilityLabel == "Running")
    #expect(AgentActivityState.needsInput.accessibilityLabel == "Needs input")
    #expect(AgentActivityState.idle.accessibilityLabel == "Idle")
    #expect(AgentActivityState.completed.accessibilityLabel == "Completed")
    #expect(AgentActivityState.exited.accessibilityLabel == "Exited")
}
```

- [ ] **Step 2: Run the enum display tests**

Run:

```bash
swift test --filter AgentActivityStateTests
```

Expected: PASS from Task 1. If this fails, fix `AgentActivityState` before touching UI.

- [ ] **Step 3: Create the badge view**

Create `Muxy/Views/Sidebar/AgentActivityBadge.swift`:

```swift
import MuxyShared
import SwiftUI

struct AgentActivityBadge: View {
    let state: AgentActivityState

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .font(.system(size: 7, weight: .bold))
            Text(state.sidebarLabel)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 5)
        .frame(height: 15)
        .background(background, in: RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel(state.accessibilityLabel)
        .help(state.accessibilityLabel)
    }

    private var symbolName: String {
        switch state {
        case .running: "play.fill"
        case .needsInput: "exclamationmark"
        case .idle: "pause.fill"
        case .completed: "checkmark"
        case .exited: "xmark"
        }
    }

    private var foreground: Color {
        switch state {
        case .running: MuxyTheme.accent
        case .needsInput: MuxyTheme.diffModifyFg
        case .idle: MuxyTheme.diffAddFg
        case .completed: MuxyTheme.diffAddFg
        case .exited: MuxyTheme.fgDim
        }
    }

    private var background: Color {
        foreground.opacity(0.12)
    }
}
```

- [ ] **Step 4: Render the badge in SessionRow**

Modify `Muxy/Views/Sidebar/SessionRow.swift`.

Add:

```swift
private var activityState: AgentActivityState {
    tab.content.pane?.activityState ?? .running
}

private var showsActivityBadge: Bool {
    agentKind != .terminal
}
```

Replace the `lifecycleDot` placement inside `HStack`:

```swift
lifecycleDot

Spacer(minLength: 0)
```

with:

```swift
Spacer(minLength: 0)

if showsActivityBadge {
    AgentActivityBadge(state: activityState)
} else {
    lifecycleDot
}
```

- [ ] **Step 5: Update process exit to drive activity state**

Modify `Muxy/Views/Workspace/TabAreaView.swift` inside `onProcessExit`:

```swift
pane.lastState = .exited
pane.activityState = .exited
```

Keep the existing terminal auto-close behavior unchanged.

- [ ] **Step 6: Run focused tests**

Run:

```bash
swift test --filter AgentActivityStateTests
swift test --filter AppStateAgentActivityTests
swift test --filter AgentTabCreationTests
```

Expected: PASS.

- [ ] **Step 7: Manual UI check**

Run:

```bash
swift run Muxy
```

Manual expectation:

- Open a Codex or Claude Code tab.
- Sidebar row shows provider icon, title, and `RUN` chip.
- Trigger a hook notification; row changes to `WAIT`.
- Trigger a stop/complete hook; row changes to `DONE`.
- Exit the agent process; row changes to `EXIT`.

- [ ] **Step 8: Commit**

Run:

```bash
jj st
jj commit -m "feat(sidebar): show agent activity badges"
```

---

## Task 7: Update Docs And Backlog

**Files:**
- Modify: `docs/notification-setup.md`
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Update notification wire format docs**

Modify `docs/notification-setup.md` under "Wire Format".

Replace:

```text
<type>|<paneID>|<title>|<body>
```

with:

```text
<type>[:<activity>]|<paneID>|<title>|<body>
```

Add this table below the existing field table:

```markdown
Optional activity suffixes update the matching sidebar agent state before the notification is delivered:

| Suffix | Sidebar state |
| --- | --- |
| `running` | Running |
| `needs_input` | Needs input |
| `idle` | Idle |
| `completed` | Completed |
| `exited` | Exited |

Built-in provider hooks use these suffixes. Custom integrations can omit the suffix and keep legacy notification-only behavior.
```

- [ ] **Step 2: Update the shell example**

In `docs/notification-setup.md`, change the reusable helper payload:

```bash
printf '%s|%s|%s|%s' "custom" "${MUXY_PANE_ID:-}" "$title" "$safe_body" \
```

to:

```bash
printf '%s|%s|%s|%s' "custom:completed" "${MUXY_PANE_ID:-}" "$title" "$safe_body" \
```

- [ ] **Step 3: Update migration backlog**

Modify `docs/roost-migration-plan.md` active backlog from:

```markdown
- sessions: richer lifecycle states beyond running/exited when reliable terminal lifecycle signals exist.
```

to:

```markdown
- sessions: terminal lifecycle remains running/exited; agent activity states are hook-driven and visible in the sidebar. Future work is real-time agent running/idle detection if provider CLIs expose reliable streaming state.
```

- [ ] **Step 4: Run docs search**

Run:

```bash
rg -n "richer lifecycle states|needs_input|AgentActivityState|<type>\\[:<activity>\\]" docs Muxy MuxyShared Tests
```

Expected:

- No stale "richer lifecycle states beyond running/exited" backlog line.
- New activity wire format and enum references exist.

- [ ] **Step 5: Commit**

Run:

```bash
jj st
jj commit -m "docs(agent): document sidebar activity states"
```

---

## Task 8: Full Verification And Final Commit Hygiene

**Files:**
- No planned file edits unless verification exposes issues.

- [ ] **Step 1: Run project auto-fix checks**

Run:

```bash
scripts/checks.sh --fix
```

Expected: command completes successfully.

- [ ] **Step 2: Run focused test suite**

Run:

```bash
swift test --filter AgentActivityStateTests
swift test --filter AgentActivitySocketEventTests
swift test --filter AppStateAgentActivityTests
swift test --filter AgentHookScriptTests
swift test --filter AgentTabCreationTests
```

Expected: PASS.

- [ ] **Step 3: Inspect pending changes**

Run:

```bash
jj st
jj diff --git
```

Expected:

- Only agent activity sidebar files, provider scripts, and docs changed.
- No debug logs, no temporary files, no unrelated formatting churn.

- [ ] **Step 4: If checks created formatting edits, commit them**

Run only if `jj st` shows changes from formatting or final fixes:

```bash
jj commit -m "fix(agent): polish sidebar activity states"
```

- [ ] **Step 5: Report manual limitations**

Final implementation report must state:

- Ghostty process exit is separate from agent activity.
- `RUN` is the initial/default live state, not proof that the model is actively generating.
- `WAIT`, `DONE`, and `IDLE` are reliable only when the provider hook emits the corresponding event.

---

## Self-Review

- Spec coverage: the plan separates terminal lifecycle from agent activity, parses hook events, updates live panes, renders sidebar status, updates provider hooks, and documents the socket contract.
- Placeholder scan: no task uses placeholder markers or vague catch-all wording; every code-changing task lists exact file paths and concrete snippets.
- Type consistency: `AgentActivityState`, `AgentActivitySocketEvent`, `activityState`, and `updateAgentActivity(paneID:state:)` names are consistent across tasks.
