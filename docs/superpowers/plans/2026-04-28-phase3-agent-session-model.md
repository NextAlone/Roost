# Phase 3 — Agent Session Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make terminal tabs agent-aware: each tab carries an `AgentKind`, ships a built-in preset command, runs in the active jj workspace's path as cwd, and survives app restart.

**Architecture:** Introduce `AgentKind` (enum) + `AgentPreset` (catalog) in `MuxyShared`. Extend `TerminalPaneState` with `agentKind` (default `.terminal`) and route the preset's `defaultCommand` through the existing `startupCommand` channel. Add `TabArea.createAgentTab(kind:)` factory; `cwd` is already implicit because `TabArea.projectPath` stores the active worktree path (verified — see `WorkspaceReducerShared.ensureWorkspaceExists`). Wire reducer + shortcut + menu entries for new agent tab types. `requiresDedicatedWorkspace` is recorded on the preset but **not enforced** in this phase — enforcement deferred to Phase 4 sidebar.

**Tech Stack:** Swift 6, SwiftUI, swift-testing, MuxyShared (cross-target framework), Roost executable target.

**Locked decisions (do not re-litigate):**
- N:1 cardinality (multiple sessions can share one workspace).
- Per-preset `requiresDedicatedWorkspace` flag exists, default `false` for all built-in presets.
- `AgentKind` is a field on `TerminalPaneState`, not a new `Content` case. Future agent-specific state (MCP config, AI usage binding) may introduce `.agent(AgentTabState)` — out of scope here.
- Preset command strings (`claude`, `codex`, etc.) use sensible defaults; user-configurable presets land in Phase 7.
- Snapshots use `decodeIfPresent` for new fields with `.terminal` / `nil` defaults — same pattern already used for `vcsKind`, `paneTitle`, etc.
- "last known state" (running/idle/exited/errored) is *not* tracked in this phase — snapshot stores agentKind + command + createdAt only. Lifecycle observation deferred.

**Out of scope (must not be added):**
- UI flow that creates a dedicated `jj workspace add` when `requiresDedicatedWorkspace == true` (Phase 4).
- Per-session "last known state" lifecycle tracking (Phase 4 sidebar badges).
- User-configurable preset definitions / `.roost/config.json` integration (Phase 7).
- Renaming `TabArea.projectPath` → `worktreePath` (chore, unrelated).

---

## File Structure

**Create:**
- `MuxyShared/Agent/AgentKind.swift` — enum + display + default command + dedicated flag table
- `MuxyShared/Agent/AgentPreset.swift` — value type + `AgentPresetCatalog`
- `Tests/MuxyTests/Agent/AgentKindTests.swift`
- `Tests/MuxyTests/Agent/AgentPresetTests.swift`
- `Tests/MuxyTests/Models/AgentTabCreationTests.swift` — covers `TabArea.createAgentTab` and reducer

**Modify:**
- `Muxy/Models/TerminalPaneState.swift` — add `agentKind`, `createdAt`
- `Muxy/Models/TerminalTab.swift` — title falls back to agent display name when no customTitle
- `Muxy/Models/TabArea.swift` — add `createAgentTab(kind:)`
- `Muxy/Models/WorkspaceSnapshot.swift` — `TerminalTabSnapshot` adds `agentKind`, `startupCommand`, `createdAt`; `TerminalTab.snapshot` / `init(restoring:)` plumbing
- `Muxy/Models/AppState.swift` — `Action.createAgentTab(projectID:areaID:kind:)`, helper `createAgentTab(_:projectID:)`
- `Muxy/Models/WorkspaceReducer.swift` — dispatch new case to `TabReducer`
- `Muxy/Models/WorkspaceReducer/TabReducer.swift` — `createAgentTab` reducer
- `Muxy/Services/ShortcutAction.swift` (or wherever the enum lives) — new actions: `.newClaudeCodeTab`, `.newCodexTab`, `.newGeminiCliTab`, `.newOpenCodeTab`
- `Muxy/Services/ShortcutActionDispatcher.swift` — dispatch new actions
- `Muxy/Commands/MuxyCommands.swift` — menu entries under New section
- `MuxyShared/KeyBinding/...` — add default key bindings (no shortcuts assigned by default; menu entries only)

**Tests modified:**
- `Tests/MuxyTests/Models/WorkspaceSnapshotTests.swift` — backward-compat decode (legacy snapshot lacks new fields), forward-compat encode/decode round-trip with agentKind set

---

## Task 1: AgentKind enum

**Files:**
- Create: `MuxyShared/Agent/AgentKind.swift`
- Test: `Tests/MuxyTests/Agent/AgentKindTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import MuxyShared
import Testing

@Suite("AgentKind")
struct AgentKindTests {
    @Test("Codable round-trips all cases")
    func codableRoundTrip() throws {
        let original = AgentKind.allCases
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([AgentKind].self, from: data)
        #expect(decoded == original)
    }

    @Test("decodes legacy raw value 'terminal'")
    func decodesTerminal() throws {
        let json = "[\"terminal\"]"
        let decoded = try JSONDecoder().decode([AgentKind].self, from: Data(json.utf8))
        #expect(decoded == [.terminal])
    }

    @Test("display names are non-empty")
    func displayNames() {
        for kind in AgentKind.allCases {
            #expect(!kind.displayName.isEmpty)
        }
    }

    @Test("unknown raw value throws")
    func unknownThrows() {
        let json = "[\"copilot\"]"
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode([AgentKind].self, from: Data(json.utf8))
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AgentKindTests`
Expected: FAIL — "cannot find 'AgentKind' in scope".

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum AgentKind: String, Sendable, Codable, Hashable, CaseIterable {
    case terminal
    case claudeCode
    case codex
    case geminiCli
    case openCode

    public var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCli: "Gemini CLI"
        case .openCode: "OpenCode"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AgentKindTests`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(agent): add AgentKind enum (terminal + 4 agents)"
```

---

## Task 2: AgentPreset + AgentPresetCatalog

**Files:**
- Create: `MuxyShared/Agent/AgentPreset.swift`
- Test: `Tests/MuxyTests/Agent/AgentPresetTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import MuxyShared
import Testing

@Suite("AgentPreset")
struct AgentPresetTests {
    @Test("catalog has a preset for every AgentKind")
    func catalogCoversAllKinds() {
        for kind in AgentKind.allCases {
            #expect(AgentPresetCatalog.preset(for: kind).kind == kind)
        }
    }

    @Test("terminal preset has no startup command")
    func terminalIsBare() {
        let preset = AgentPresetCatalog.preset(for: .terminal)
        #expect(preset.defaultCommand == nil)
        #expect(preset.requiresDedicatedWorkspace == false)
    }

    @Test("non-terminal presets have a default command")
    func agentsHaveCommand() {
        for kind in AgentKind.allCases where kind != .terminal {
            let preset = AgentPresetCatalog.preset(for: kind)
            #expect(preset.defaultCommand?.isEmpty == false)
        }
    }

    @Test("requiresDedicatedWorkspace defaults to false for all built-ins")
    func dedicatedDefaultsFalse() {
        for kind in AgentKind.allCases {
            #expect(AgentPresetCatalog.preset(for: kind).requiresDedicatedWorkspace == false)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AgentPresetTests`
Expected: FAIL — `AgentPreset` not in scope.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public struct AgentPreset: Sendable, Hashable {
    public let kind: AgentKind
    public let defaultCommand: String?
    public let requiresDedicatedWorkspace: Bool

    public init(kind: AgentKind, defaultCommand: String?, requiresDedicatedWorkspace: Bool = false) {
        self.kind = kind
        self.defaultCommand = defaultCommand
        self.requiresDedicatedWorkspace = requiresDedicatedWorkspace
    }
}

public enum AgentPresetCatalog {
    public static func preset(for kind: AgentKind) -> AgentPreset {
        switch kind {
        case .terminal:
            return AgentPreset(kind: .terminal, defaultCommand: nil)
        case .claudeCode:
            return AgentPreset(kind: .claudeCode, defaultCommand: "claude")
        case .codex:
            return AgentPreset(kind: .codex, defaultCommand: "codex")
        case .geminiCli:
            return AgentPreset(kind: .geminiCli, defaultCommand: "gemini")
        case .openCode:
            return AgentPreset(kind: .openCode, defaultCommand: "opencode")
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AgentPresetTests`
Expected: PASS — 4 tests.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(agent): add AgentPreset + built-in catalog"
```

---

## Task 3: TerminalPaneState carries agentKind + createdAt

**Files:**
- Modify: `Muxy/Models/TerminalPaneState.swift`

- [ ] **Step 1: Read the existing file to see current init signature**

Run: `cat Muxy/Models/TerminalPaneState.swift`

- [ ] **Step 2: Write the modified file**

```swift
import Foundation
import MuxyShared

@MainActor
@Observable
final class TerminalPaneState: Identifiable {
    let id = UUID()
    let projectPath: String
    var title: String
    let startupCommand: String?
    let externalEditorFilePath: String?
    let agentKind: AgentKind
    let createdAt: Date
    let searchState = TerminalSearchState()
    @ObservationIgnored private var titleDebounceTask: Task<Void, Never>?

    init(
        projectPath: String,
        title: String = "Terminal",
        startupCommand: String? = nil,
        externalEditorFilePath: String? = nil,
        agentKind: AgentKind = .terminal,
        createdAt: Date = Date()
    ) {
        self.projectPath = projectPath
        self.title = title
        self.startupCommand = startupCommand
        self.externalEditorFilePath = externalEditorFilePath
        self.agentKind = agentKind
        self.createdAt = createdAt
    }

    func setTitle(_ newTitle: String) {
        titleDebounceTask?.cancel()
        titleDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.title != newTitle else { return }
            self.title = newTitle
        }
    }
}
```

- [ ] **Step 3: Build to confirm no callsite breaks**

Run: `swift build 2>&1 | head -30`
Expected: SUCCESS — both new params have defaults, existing callsites compile.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(terminal): TerminalPaneState carries agentKind + createdAt"
```

---

## Task 4: TabArea.createAgentTab(kind:)

**Files:**
- Modify: `Muxy/Models/TabArea.swift`
- Test: `Tests/MuxyTests/Models/AgentTabCreationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("Agent tab creation")
struct AgentTabCreationTests {
    @Test("createAgentTab(.terminal) is identical to createTab")
    func terminalCase() {
        let area = TabArea(projectPath: "/tmp/wt")
        let countBefore = area.tabs.count
        area.createAgentTab(kind: .terminal)
        #expect(area.tabs.count == countBefore + 1)
        let pane = area.activeTab?.content.pane
        #expect(pane?.agentKind == .terminal)
        #expect(pane?.startupCommand == nil)
    }

    @Test("createAgentTab(.claudeCode) sets agentKind + preset command")
    func claudeCase() {
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        let pane = area.activeTab?.content.pane
        #expect(pane?.agentKind == .claudeCode)
        #expect(pane?.startupCommand == "claude")
        #expect(pane?.projectPath == "/tmp/wt")
    }

    @Test("createAgentTab(.codex) cwd is the TabArea projectPath (active worktree)")
    func cwdEqualsWorktreePath() {
        let area = TabArea(projectPath: "/Users/me/repo/wt-feature-x")
        area.createAgentTab(kind: .codex)
        let pane = area.activeTab?.content.pane
        #expect(pane?.projectPath == "/Users/me/repo/wt-feature-x")
        #expect(pane?.startupCommand == "codex")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AgentTabCreationTests`
Expected: FAIL — `createAgentTab` not in scope.

- [ ] **Step 3: Add `createAgentTab` to TabArea**

In `Muxy/Models/TabArea.swift`, after `createTab(inDirectory:)` (around line 64):

```swift
func createAgentTab(kind: AgentKind) {
    let preset = AgentPresetCatalog.preset(for: kind)
    let pane = TerminalPaneState(
        projectPath: projectPath,
        title: preset.kind.displayName,
        startupCommand: preset.defaultCommand,
        agentKind: kind
    )
    insertTab(TerminalTab(pane: pane))
}
```

Add `import MuxyShared` at the top of `TabArea.swift` if not already present.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AgentTabCreationTests`
Expected: PASS — 3 tests.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(tabs): TabArea.createAgentTab uses preset + active worktree cwd"
```

---

## Task 5: Snapshot persistence (agentKind + startupCommand + createdAt)

**Files:**
- Modify: `Muxy/Models/WorkspaceSnapshot.swift`
- Modify: `Muxy/Models/TerminalTab.swift`
- Test: `Tests/MuxyTests/Models/WorkspaceSnapshotTests.swift`

- [ ] **Step 1: Add backward-compat + round-trip tests to WorkspaceSnapshotTests**

Append two new tests in `Tests/MuxyTests/Models/WorkspaceSnapshotTests.swift`:

```swift
@Test("legacy snapshot without agentKind decodes as .terminal")
func legacyDecodes() throws {
    let json = """
    {
      "kind": "terminal",
      "customTitle": null,
      "colorID": null,
      "isPinned": false,
      "projectPath": "/tmp/p",
      "paneTitle": "Terminal",
      "filePath": null
    }
    """
    let snap = try JSONDecoder().decode(TerminalTabSnapshot.self, from: Data(json.utf8))
    #expect(snap.agentKind == .terminal)
    #expect(snap.startupCommand == nil)
}

@Test("agent snapshot round-trips agentKind + startupCommand")
func agentRoundTrips() throws {
    let original = TerminalTabSnapshot(
        kind: .terminal,
        customTitle: nil,
        colorID: nil,
        isPinned: false,
        projectPath: "/tmp/wt",
        paneTitle: "Claude Code",
        filePath: nil,
        agentKind: .claudeCode,
        startupCommand: "claude",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TerminalTabSnapshot.self, from: data)
    #expect(decoded.agentKind == .claudeCode)
    #expect(decoded.startupCommand == "claude")
    #expect(decoded.createdAt == original.createdAt)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WorkspaceSnapshotTests`
Expected: FAIL — `agentKind`, `startupCommand`, `createdAt` not on `TerminalTabSnapshot`; init signature mismatch.

- [ ] **Step 3: Extend `TerminalTabSnapshot`**

Replace the struct in `Muxy/Models/WorkspaceSnapshot.swift` (currently lines 100-147):

```swift
struct TerminalTabSnapshot: Codable {
    let kind: TerminalTab.Kind
    let customTitle: String?
    let colorID: String?
    let isPinned: Bool
    let projectPath: String
    let paneTitle: String
    let filePath: String?
    let agentKind: AgentKind
    let startupCommand: String?
    let createdAt: Date

    init(
        kind: TerminalTab.Kind,
        customTitle: String?,
        colorID: String?,
        isPinned: Bool,
        projectPath: String,
        paneTitle: String?,
        filePath: String? = nil,
        agentKind: AgentKind = .terminal,
        startupCommand: String? = nil,
        createdAt: Date = Date()
    ) {
        self.kind = kind
        self.customTitle = customTitle
        self.colorID = colorID
        self.isPinned = isPinned
        self.projectPath = projectPath
        self.paneTitle = paneTitle ?? "Terminal"
        self.filePath = filePath
        self.agentKind = agentKind
        self.startupCommand = startupCommand
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case customTitle
        case colorID
        case isPinned
        case projectPath
        case paneTitle
        case filePath
        case agentKind
        case startupCommand
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(TerminalTab.Kind.self, forKey: .kind) ?? .terminal
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        colorID = try container.decodeIfPresent(String.self, forKey: .colorID)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        projectPath = try container.decode(String.self, forKey: .projectPath)
        paneTitle = try container.decodeIfPresent(String.self, forKey: .paneTitle) ?? "Terminal"
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        agentKind = try container.decodeIfPresent(AgentKind.self, forKey: .agentKind) ?? .terminal
        startupCommand = try container.decodeIfPresent(String.self, forKey: .startupCommand)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}
```

Add `import MuxyShared` at the top of `WorkspaceSnapshot.swift` if missing.

- [ ] **Step 4: Update `TerminalTab.snapshot()` to populate the new fields**

In `Muxy/Models/TerminalTab.swift`, replace the `snapshot()` method (currently lines 118-128):

```swift
func snapshot() -> TerminalTabSnapshot {
    TerminalTabSnapshot(
        kind: content.kind,
        customTitle: customTitle,
        colorID: colorID,
        isPinned: isPinned,
        projectPath: content.projectPath,
        paneTitle: content.pane?.title,
        filePath: content.editorState?.filePath,
        agentKind: content.pane?.agentKind ?? .terminal,
        startupCommand: content.pane?.startupCommand,
        createdAt: content.pane?.createdAt ?? Date()
    )
}
```

- [ ] **Step 5: Update `TerminalTab.init(restoring:)` to thread new fields back into the pane**

In `Muxy/Models/TerminalTab.swift`, replace the `init(restoring:)` body (currently lines 98-116):

```swift
init(restoring snapshot: TerminalTabSnapshot) {
    customTitle = snapshot.customTitle
    colorID = snapshot.colorID
    isPinned = snapshot.isPinned
    switch snapshot.kind {
    case .terminal:
        content = .terminal(TerminalPaneState(
            projectPath: snapshot.projectPath,
            title: snapshot.paneTitle,
            startupCommand: snapshot.startupCommand,
            agentKind: snapshot.agentKind,
            createdAt: snapshot.createdAt
        ))
    case .vcs:
        content = .vcs(VCSTabState(projectPath: snapshot.projectPath))
    case .editor:
        if let filePath = snapshot.filePath {
            content = .editor(EditorTabState(projectPath: snapshot.projectPath, filePath: filePath))
        } else {
            content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
        }
    case .diffViewer:
        content = .terminal(TerminalPaneState(projectPath: snapshot.projectPath, title: snapshot.paneTitle))
    }
}
```

Add `import MuxyShared` at the top of `TerminalTab.swift` if missing.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter WorkspaceSnapshotTests`
Expected: PASS — all existing + 2 new tests.

- [ ] **Step 7: Commit**

```bash
jj commit -m "feat(persistence): TerminalTabSnapshot persists agentKind + command + createdAt"
```

---

## Task 6: TerminalTab title falls back to agent display name

**Files:**
- Modify: `Muxy/Models/TerminalTab.swift`
- Test: `Tests/MuxyTests/Models/AgentTabCreationTests.swift`

- [ ] **Step 1: Add a title test**

Append to `AgentTabCreationTests`:

```swift
@Test("Claude Code tab default title shows agent name")
func claudeTabTitle() {
    let area = TabArea(projectPath: "/tmp/wt")
    area.createAgentTab(kind: .claudeCode)
    #expect(area.activeTab?.title == "Claude Code")
}

@Test("custom title overrides agent display name")
func customTitleWins() {
    let area = TabArea(projectPath: "/tmp/wt")
    area.createAgentTab(kind: .codex)
    let tab = area.activeTab
    tab?.customTitle = "Codex (debug)"
    #expect(tab?.title == "Codex (debug)")
}
```

- [ ] **Step 2: Run to verify behaviour**

Run: `swift test --filter AgentTabCreationTests`

The first test may already pass because `TerminalPaneState.title` is set to `preset.kind.displayName` in Task 4 — confirm. If both pass, move to commit. If the first test fails because pane title comes from elsewhere, adjust the title computation in `TerminalTab.title` to fall back to `pane.agentKind.displayName` when `pane.title == "Terminal"` and `agentKind != .terminal`. Add the explicit fallback only if the test fails.

- [ ] **Step 3: Commit**

```bash
jj commit -m "test(tabs): agent tab title comes from preset display name"
```

---

## Task 7: Reducer + AppState dispatch for createAgentTab

**Files:**
- Modify: `Muxy/Models/AppState.swift`
- Modify: `Muxy/Models/WorkspaceReducer.swift`
- Modify: `Muxy/Models/WorkspaceReducer/TabReducer.swift`
- Test: `Tests/MuxyTests/Models/AgentTabCreationTests.swift`

- [ ] **Step 1: Add an integration test that exercises the reducer path**

Append to `AgentTabCreationTests`:

```swift
@Test("AppState.createAgentTab opens pane in active worktree path")
func reducerRoutesCwd() async throws {
    let projectStore = ProjectStore()
    let worktreeStore = WorktreeStore()
    let appState = AppState(projectStore: projectStore, worktreeStore: worktreeStore)

    let project = Project(name: "demo", path: "/tmp/demo")
    projectStore.add(project)
    let primary = Worktree(
        name: "main",
        path: "/tmp/demo",
        branch: "main",
        isPrimary: true,
        vcsKind: .jj
    )
    worktreeStore.set([primary], for: project.id)
    appState.activateProject(project.id)

    appState.createAgentTab(.claudeCode, projectID: project.id)

    let area = appState.focusedArea(for: project.id)
    let pane = area?.activeTab?.content.pane
    #expect(pane?.agentKind == .claudeCode)
    #expect(pane?.startupCommand == "claude")
    #expect(pane?.projectPath == "/tmp/demo")
}
```

If `AppState.activateProject` / `focusedArea` helpers do not exist with these exact names, mirror what other reducer-level tests in the suite use — read `Tests/MuxyTests/Models/WorkspaceSnapshotTests.swift` first and copy the same setup pattern.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter AgentTabCreationTests/reducerRoutesCwd`
Expected: FAIL — `createAgentTab` not on `AppState`.

- [ ] **Step 3: Add the action case in `AppState.swift`**

In `Muxy/Models/AppState.swift`, add to the `Action` enum (around line 33-35, next to `createTab`):

```swift
case createAgentTab(projectID: UUID, areaID: UUID?, kind: AgentKind)
```

Add a helper near the existing `createTab(projectID:)` (around line 205-210):

```swift
func createAgentTab(_ kind: AgentKind, projectID: UUID) {
    dispatch(.createAgentTab(projectID: projectID, areaID: nil, kind: kind))
}
```

Ensure `import MuxyShared` is present (likely already imported).

- [ ] **Step 4: Wire the case into `WorkspaceReducer.swift`**

In `Muxy/Models/WorkspaceReducer.swift`, add a case alongside `.createTab` (around line 71-75):

```swift
case let .createAgentTab(projectID, areaID, kind):
    TabReducer.createAgentTab(projectID: projectID, areaID: areaID, kind: kind, state: &state)
```

- [ ] **Step 5: Add the reducer in `TabReducer.swift`**

In `Muxy/Models/WorkspaceReducer/TabReducer.swift`, after `createTabInDirectory` (around line 24):

```swift
static func createAgentTab(
    projectID: UUID,
    areaID: UUID?,
    kind: AgentKind,
    state: inout WorkspaceState
) {
    guard let key = WorkspaceReducerShared.activeKey(projectID: projectID, state: state),
          let area = WorkspaceReducerShared.resolveArea(key: key, areaID: areaID, state: state)
    else { return }
    FocusReducer.focusArea(area.id, key: key, state: &state)
    area.createAgentTab(kind: kind)
}
```

Add `import MuxyShared` at the top of `TabReducer.swift` if missing.

- [ ] **Step 6: Run the integration test**

Run: `swift test --filter AgentTabCreationTests/reducerRoutesCwd`
Expected: PASS.

- [ ] **Step 7: Run the whole suite to check for regressions**

Run: `swift test 2>&1 | tail -20`
Expected: all green.

- [ ] **Step 8: Commit**

```bash
jj commit -m "feat(reducer): createAgentTab routes through focused area"
```

---

## Task 8: Shortcut actions + menu entries

**Files:**
- Modify: `Muxy/Services/ShortcutAction.swift` (or wherever the enum is defined — grep first)
- Modify: `Muxy/Services/ShortcutActionDispatcher.swift`
- Modify: `Muxy/Commands/MuxyCommands.swift`

- [ ] **Step 1: Locate the ShortcutAction enum**

Run: `grep -rn "enum ShortcutAction\b\|case newTab\b" Muxy/ --include="*.swift" | head -5`

Open the file containing `case newTab` and the file containing `enum ShortcutAction`.

- [ ] **Step 2: Add four new cases**

Add to `ShortcutAction`:

```swift
case newClaudeCodeTab
case newCodexTab
case newGeminiCliTab
case newOpenCodeTab
```

If `ShortcutAction` is a `String` enum used for binding persistence, ensure the new raw values are stable strings (`"newClaudeCodeTab"`, etc.) so they persist correctly.

- [ ] **Step 3: Dispatch them in `ShortcutActionDispatcher.swift`**

After the existing `.newTab` handler (around line 45), add:

```swift
case .newClaudeCodeTab:
    guard let projectID = activeProject?.id else { return false }
    appState.createAgentTab(.claudeCode, projectID: projectID)
case .newCodexTab:
    guard let projectID = activeProject?.id else { return false }
    appState.createAgentTab(.codex, projectID: projectID)
case .newGeminiCliTab:
    guard let projectID = activeProject?.id else { return false }
    appState.createAgentTab(.geminiCli, projectID: projectID)
case .newOpenCodeTab:
    guard let projectID = activeProject?.id else { return false }
    appState.createAgentTab(.openCode, projectID: projectID)
```

Match the surrounding switch's return-`Bool` / `return true` convention — read 10 lines of context before editing.

- [ ] **Step 4: Add menu entries to `MuxyCommands.swift`**

In `CommandGroup(replacing: .newItem)` block (around line 95-135), insert after the existing "Source Control" button:

```swift
Divider()

Button("New Claude Code Tab") {
    guard isMainWindowFocused else { return }
    performShortcutAction(.newClaudeCodeTab)
}
.shortcut(for: .newClaudeCodeTab, store: keyBindings)

Button("New Codex Tab") {
    guard isMainWindowFocused else { return }
    performShortcutAction(.newCodexTab)
}
.shortcut(for: .newCodexTab, store: keyBindings)

Button("New Gemini CLI Tab") {
    guard isMainWindowFocused else { return }
    performShortcutAction(.newGeminiCliTab)
}
.shortcut(for: .newGeminiCliTab, store: keyBindings)

Button("New OpenCode Tab") {
    guard isMainWindowFocused else { return }
    performShortcutAction(.newOpenCodeTab)
}
.shortcut(for: .newOpenCodeTab, store: keyBindings)
```

Default key bindings: leave unset (no automatic shortcut). Users can bind via Settings.

- [ ] **Step 5: Build and verify menu entries appear**

Run: `swift build 2>&1 | tail -20`
Expected: SUCCESS.

Manual smoke (after `swift run Muxy`):
- File menu shows the four new entries.
- With a project open, clicking "New Claude Code Tab" opens a new tab; pane title is "Claude Code"; the terminal shell launches `claude` in the active worktree path.
- Quitting + relaunching restores the agent tab with the right title (because snapshot now persists agentKind).

If a default key binding storage requires every action have a `defaultBinding`, add `nil` entries (no default).

- [ ] **Step 6: Run full test suite**

Run: `scripts/checks.sh --fix`
Expected: lint + format + tests all pass.

- [ ] **Step 7: Commit**

```bash
jj commit -m "feat(commands): menu entries for new agent tabs"
```

---

## Task 9: Migration plan note + close-out

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Update Phase 3 section**

Locate the Phase 3 block (around line 312). Add at the bottom of the section:

```markdown
**Status (2026-04-28): Phase 3 implementation landed.**

- AgentKind + AgentPreset live in MuxyShared.
- TerminalPaneState carries `agentKind` + `createdAt`. Snapshot persists both plus startupCommand (decode-tolerant).
- `TabArea.createAgentTab` + `AppState.createAgentTab` route preset command into the active worktree path (cwd).
- Menu entries: New Claude Code / Codex / Gemini CLI / OpenCode Tab.
- `requiresDedicatedWorkspace` flag exists on `AgentPreset` but is **not enforced** (all built-ins default `false`); enforcement → Phase 4 sidebar work.
- "Last known state" lifecycle (running/idle/exited/errored) **deferred** to Phase 4 status badges.
- User-configurable presets / `.roost/config.json` integration → Phase 7.
```

- [ ] **Step 2: Run final checks**

Run: `scripts/checks.sh`
Expected: all green.

- [ ] **Step 3: Commit**

```bash
jj commit -m "docs(plan): mark Phase 3 implementation landed"
```

---

## Self-Review Checklist

- [ ] All exit criteria covered:
  - Create Terminal/Claude/Codex tabs from UI shortcuts → Tasks 7-8.
  - Agent tab cwd is the active jj workspace → Task 4 (TabArea.projectPath = worktreePath, verified) + Task 7 (reducer test).
  - Agent kind is visible in tab/session metadata → Task 3 + Task 5 + Task 6.
  - Session metadata survives app restart where possible → Task 5 (snapshot round-trip + legacy decode).
- [ ] No placeholders ("TODO", "implement later", "similar to Task N").
- [ ] Type names consistent: `AgentKind`, `AgentPreset`, `AgentPresetCatalog`, `createAgentTab`, `.newClaudeCodeTab` (camelCase, not `claude_code`).
- [ ] Backward compat: every new snapshot field uses `decodeIfPresent` with sane default.
- [ ] No scope creep: dedicated workspace flow, lifecycle state, configurable presets all explicitly out of scope.
- [ ] Tests precede implementation in every coding task.
- [ ] Each commit is one atomic change; ~9 commits total.
