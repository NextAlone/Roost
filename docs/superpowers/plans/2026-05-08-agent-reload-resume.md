# Agent Reload and Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow the user to reload a running coding agent inside its existing pane after the agent's binary has been upgraded, preserving the conversation session by stitching the resume command (captured from the agent's exit output via tmux) onto the user's preset command.

**Architecture:** The `hostdOwnedProcess` runtime hosts agents inside `tmux new-session`. We add `set-option remain-on-exit on` to the launch, poll `pane_dead` after exit, and use `tmux capture-pane -p -S -200 -N` to read the agent's last output. A regex (per `AgentKind`, overridable per preset) extracts the resume invocation. `AppState.reloadAgent` orchestrates an imperative tear-down (`terminateSession` + `removeView`) followed by a fresh `createSession` reusing the same `paneID` but a new `sessionID`, with `GhosttyTerminalRepresentable.id(pane.sessionID)` driving SwiftUI to recreate the NSView.

**Tech Stack:** Swift 6, SwiftUI, libghostty, tmux 3.5+, SwiftPM, jj for VCS.

**Spec:** `docs/superpowers/specs/2026-05-08-agent-reload-resume-design.md`

---

## Scope and Boundaries

- Scope is `hostdOwnedProcess` runtime only. The `metadataOnly` runtime is gated off via `pane.hostdRuntimeOwnership == .hostdOwnedProcess` for both menu items and banners.
- `.terminal` agent kind is excluded; reload semantics only apply to coding agents.
- No keyboard shortcut. UI surfaces are the pane context menu, an exit banner, and a binary-update banner.
- Banner detection for binary updates is lazy (on pane focus + scenePhase change). No FSEvents.
- Resume support targets Claude Code (flag-based, `appendArgs` strategy) and Codex (subcommand-based, `replaceWithCaptured` strategy). Gemini CLI and OpenCode keep `notSupported`; their reload only runs `.fresh`.
- The implementation is gated behind a runtime-feature flag for the first land so we can disable the new menu items / banners if a regression escapes; the flag is removed in a follow-up after one release.

## File Structure

### Phase 0 — Validation

- Create `Tests/MuxyTests/Fixtures/agent-exit-claude.txt` (recorded real Claude exit)
- Create `Tests/MuxyTests/Fixtures/agent-exit-codex.txt` (recorded real Codex exit)
- Create `docs/superpowers/notes/2026-05-08-resume-validation.md` (recorded behavior, CLI acceptance results)

### Phase 1 — Data layer

- Modify `MuxyShared/Agent/AgentKind.swift` — add `defaultResumeRegex`, `resumeStrategy`, `expectedBinaryName`
- Modify `MuxyShared/Agent/AgentPreset.swift` — add `resumeCommandRegex: String?`
- Modify `MuxyShared/Config/RoostConfig.swift` — add `resumeCommandRegex` to `RoostConfigAgentPreset` + `RoostConfigAgentPresetTolerant` + `CodingKeys`
- Modify `MuxyShared/Agent/AgentPreset.swift` (catalog) — thread `resumeCommandRegex` through `AgentPresetCatalog.preset(for:env:configuredPresets:)`
- Modify `Muxy/Models/TerminalPaneState.swift` — add `sessionID`, `capturedResumeCommand`, `agentBinaryPath`, `agentBinaryMTime`, `binaryUpdateDetected`, `exitBannerDismissed`, `mtimeBannerDismissed`
- Modify `Muxy/Models/WorkspaceSnapshot.swift` — persist `sessionID` in `TerminalTabSnapshot`
- Modify `RoostHostdCore/SessionStore.swift` — add `lastTail` field + SQLite migration v1→v2 (`ALTER TABLE sessions ADD COLUMN last_tail TEXT`)
- Modify `RoostHostdCore/SessionRecord.swift` — add `let lastTail: String?` and update initializers
- Modify `RoostHostdCore/HostdAttachSocketMessages.swift` — bump `currentProtocolVersion` 7→8, extend `HostdSessionExitNotice` with `lastTail: String?`

### Phase 2 — Command building

- Create `MuxyShared/Agent/AgentBinary.swift` — `resolvePath`, `stripBinaryName`
- Create `MuxyShared/Agent/ResumeArgs.swift` — `containsShellMetacharacters`, `captureLooksValid`
- Create `MuxyShared/Agent/AgentReloadCommandBuilder.swift` — `buildReloadCommand(preset:captured:mode:)`
- Create `Tests/MuxyTests/Agent/AgentBinaryTests.swift`
- Create `Tests/MuxyTests/Agent/ResumeArgsTests.swift`
- Create `Tests/MuxyTests/Agent/AgentReloadCommandBuilderTests.swift`

### Phase 3 — Tmux capture

- Modify `RoostHostdCore/HostdTmuxSession.swift` — extend `HostdTmuxControlling` protocol with `isPaneDead`, `captureLastTail`; implement on `HostdTmuxController`; add `remain-on-exit on` to `launchArguments`
- Modify `RoostHostdCore/HostdProcessRegistry.swift` — add `startTmuxExitWatcher`; call from `launchTmuxSession`
- Modify `Tests/MuxyTests/Terminal/TerminalPaneEnvironmentTests.swift` — adjust expectations for new tmux options
- Create `Tests/MuxyTests/Hostd/HostdTmuxControllerCaptureTests.swift` — integration with real `tmux`

### Phase 4 — Client API

- Modify `Muxy/Services/Hostd/RoostHostdClient.swift` — add `func interruptSession(id: UUID) async throws`
- Modify `Muxy/Services/Hostd/RoostHostdClient.swift` — `LocalHostdClient.interruptSession`
- Modify `Muxy/Services/Hostd/XPCHostdClient.swift` — `interruptSession`
- Modify `Muxy/Services/Hostd/HostdSocketTransport.swift` — `interruptSession(_ request: Data)` + protocol entry
- Modify `RoostHostdCore/HostdAttachSocketMessages.swift` — add `HostdInterruptSessionRequest`
- Modify `RoostHostdCore/HostdDaemonSocketServer.swift` — route `interruptSession` → `HostdProcessRegistry.interruptTmuxSession(id)`
- Modify `RoostHostdCore/HostdProcessRegistry.swift` — `interruptTmuxSession(id:)` runs `tmux send-keys -t <name> C-c`

### Phase 5 — App orchestration

- Modify `Muxy/Models/AppState.swift` — `handleSessionExit`, `refreshBinaryUpdateBanner`, `reloadAgent`
- Modify `Muxy/Models/AppState.swift` (Action enum) — add `.markPaneSessionExited`, `.reloadAgent`, `.setBinaryUpdateDetected`, `.dismissExitBanner`, `.dismissBinaryUpdateBanner`
- Modify `Muxy/Models/WorkspaceReducer.swift` — handle the new actions
- Create `Muxy/Services/AgentReload/AgentReloadCoordinator.swift` — SIGINT tiered timeout
- Modify `Muxy/Services/ActivityLogStore.swift` — `.agentExited(paneID, captured: Bool)`, `.agentReloaded(paneID, mode:)`
- Modify `MuxyShared/Agent/AgentActivityEvent.swift` — extend with the two variants
- Modify `Muxy/Models/Hostd/HostdSessionEventBridge.swift` (or wherever exit events land) — pass `lastTail` to `AppState.handleSessionExit`

### Phase 6 — UI

- Modify `Muxy/Views/Workspace/TerminalPaneContextMenu.swift` — add "Reload Agent (Resume)" / "Reload Agent (Fresh)"
- Create `Muxy/Views/Terminal/AgentReloadBanner.swift` — exit banner + binary-update banner (single `View` with two layouts)
- Modify `Muxy/Views/Terminal/TerminalPane.swift` — overlay `AgentReloadBanner`; bind `GhosttyTerminalRepresentable` with `.id(pane.sessionID)`; trigger `refreshBinaryUpdateBanner` on focus / scenePhase

### Phase 7 — Integration + docs

- Create `Tests/MuxyTests/Integration/AgentReloadIntegrationTests.swift` — gated on `tmux` presence
- Modify `docs/architecture.md` — add a short "Agent Reload" subsection under Hostd Live Attach

---

# Phase 0: Validation

These tasks must complete before any production code is written. They produce concrete artifacts (fixtures, recorded behavior notes) that the rest of the plan depends on.

## Task 0.1: Capture real Claude Code exit output

**Files:**
- Create: `Tests/MuxyTests/Fixtures/agent-exit-claude.txt`
- Create: `docs/superpowers/notes/2026-05-08-resume-validation.md`

- [ ] **Step 1: Run a Claude session to a clean exit and capture output**

In a terminal:

```bash
mkdir -p Tests/MuxyTests/Fixtures docs/superpowers/notes
SID=val-claude-$$
tmux kill-session -t $SID 2>/dev/null
tmux new-session -d -s $SID -- claude --dangerously-skip-permissions \; set-option -t $SID remain-on-exit on
# Inside Claude (manually attach in another shell): say "hi", then /exit
tmux attach -t $SID
# After /exit, detach with C-b d (or just close the terminal)
sleep 1
tmux capture-pane -t $SID:0.0 -p -S -200 -N > Tests/MuxyTests/Fixtures/agent-exit-claude.txt
tmux kill-session -t $SID
```

Inspect the captured file. Confirm it contains a literal resume invocation line (e.g. `claude --resume <id>` or `claude --continue`). Trim incidental noise but keep at least 30 lines of the real tail.

- [ ] **Step 2: Record observed format in the validation notes**

Create `docs/superpowers/notes/2026-05-08-resume-validation.md`:

```markdown
# Resume Validation Notes (2026-05-08)

## Claude Code

- Version captured: <run `claude --version` and paste here>
- Exit prompt observed: <copy the literal line(s)>
- Regex that matches the captured line:
  `<the regex you propose for AgentKind.claudeCode>`
- CLI acceptance check:
  - `claude --dangerously-skip-permissions --resume <id>` resumes the prior session: yes / no
  - If no, document the alternative invocation Claude actually requires.

## Codex (filled in Task 0.2)

## Tmux capture observations (filled in Task 0.5)
```

- [ ] **Step 3: Commit**

```bash
jj commit -m "test(agent): capture real Claude Code exit fixture"
```

## Task 0.2: Capture real Codex exit output

**Files:**
- Create: `Tests/MuxyTests/Fixtures/agent-exit-codex.txt`
- Modify: `docs/superpowers/notes/2026-05-08-resume-validation.md`

- [ ] **Step 1: Run a Codex session to a clean exit and capture output**

```bash
SID=val-codex-$$
tmux kill-session -t $SID 2>/dev/null
tmux new-session -d -s $SID -- codex --disable apps --dangerously-bypass-approvals-and-sandbox \; set-option -t $SID remain-on-exit on
tmux attach -t $SID
# Inside Codex: type "/exit" or whatever Codex's exit command is
sleep 1
tmux capture-pane -t $SID:0.0 -p -S -200 -N > Tests/MuxyTests/Fixtures/agent-exit-codex.txt
tmux kill-session -t $SID
```

- [ ] **Step 2: Verify Codex resume invocation actually works**

Pick the resume id Codex printed and run it manually:

```bash
codex resume <id>
```

Confirm it loads the previous session. Then verify whether running `codex --disable apps --dangerously-bypass-approvals-and-sandbox resume <id>` is **accepted or rejected** by the CLI. If rejected, the `replaceWithCaptured` strategy in the spec is the right call (preset flags drop on resume). If accepted, the spec can be revisited later but the implementation here still uses `replaceWithCaptured` for safety.

- [ ] **Step 3: Append observations to the validation notes**

Open `docs/superpowers/notes/2026-05-08-resume-validation.md` and fill in the "Codex" section: version, observed exit prompt, proposed regex, whether `<preset_flags> resume <id>` is accepted, and whether `replaceWithCaptured` is correct.

- [ ] **Step 4: Commit**

```bash
jj commit -m "test(agent): capture real Codex exit fixture"
```

## Task 0.3: Validate tmux capture on wrapped lines

**Files:**
- Modify: `docs/superpowers/notes/2026-05-08-resume-validation.md`

- [ ] **Step 1: Run a deliberately narrow tmux pane to force wrapping**

```bash
SID=val-wrap-$$
tmux kill-session -t $SID 2>/dev/null
tmux new-session -d -s $SID -x 40 -y 24 -- bash -c '
  printf "Resume with: claude --resume "
  python3 -c "print(\"x\"*200)"
  exit 0
' \; set-option -t $SID remain-on-exit on
sleep 0.5
echo "=== with -N ==="
tmux capture-pane -t $SID:0.0 -p -S -50 -N
echo "=== with -N -J ==="
tmux capture-pane -t $SID:0.0 -p -S -50 -N -J
tmux kill-session -t $SID
```

- [ ] **Step 2: Decide whether `-J` (join wrapped lines) is needed**

If the `-N` output splits the resume command into two visible lines but `-N -J` joins them, the implementation will use `-N -J` so wrapped resume commands survive capture. Record the decision in the notes file.

- [ ] **Step 3: Commit**

```bash
jj commit -m "test(tmux): validate capture-pane on wrapped lines"
```

## Task 0.4: Validate Claude Code Ctrl-C exit behavior

**Files:**
- Modify: `docs/superpowers/notes/2026-05-08-resume-validation.md`

The SIGINT tiered timeout (3s + 3s + force-kill) in Tasks 5.5 / 5.6 assumes that one or two `Ctrl-C` presses are enough to make Claude print its resume hint and exit. Verify this against the actual binary before locking in the timeout numbers.

- [ ] **Step 1: Run a Claude session and interrupt it**

```bash
SID=val-claude-c-$$
tmux kill-session -t $SID 2>/dev/null
tmux new-session -d -s $SID -- claude --dangerously-skip-permissions \; set-option -t $SID remain-on-exit on
tmux attach -t $SID
# Inside Claude: ask a long-running question (e.g. "summarize this paper").
# While Claude is still streaming a response, press Ctrl-C ONCE.
# Observe whether Claude exits, asks "Press Ctrl-C again to exit", or just stops the in-flight response.
```

- [ ] **Step 2: If Claude does not exit on the first Ctrl-C, press it again**

Record:
- Whether Claude prints a resume hint after the first Ctrl-C, the second, both, or neither.
- The total wall-clock time between the first Ctrl-C and the resume hint appearing.

- [ ] **Step 3: Repeat for Codex**

Same procedure with the Codex preset command.

- [ ] **Step 4: Update the validation notes file**

Append a "Ctrl-C exit behavior" section with the observed behavior. If the timing exceeds 3 seconds for either agent, raise the `interruptStep` constant in `AgentReloadCoordinator` (Task 5.5) before landing — pick a value that covers the observed time with at least 1 second of margin.

- [ ] **Step 5: Commit**

```bash
jj commit -m "test(agent): record Claude/Codex Ctrl-C exit behavior"
```

---

# Phase 1: Data Layer

## Task 1.1: Add `AgentKind.defaultResumeRegex` and `expectedBinaryName`

**Files:**
- Modify: `MuxyShared/Agent/AgentKind.swift`
- Create: `Tests/MuxyTests/Agent/AgentKindResumeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MuxyTests/Agent/AgentKindResumeTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@Suite("AgentKind resume metadata")
struct AgentKindResumeTests {
    @Test
    func claudeRegexMatchesCapturedFixture() throws {
        let url = Bundle.module.url(forResource: "agent-exit-claude", withExtension: "txt")!
        let text = try String(contentsOf: url, encoding: .utf8)
        let pattern = AgentKind.claudeCode.defaultResumeRegex!
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        #expect(regex.firstMatch(in: text, range: range) != nil)
    }

    @Test
    func codexRegexMatchesCapturedFixture() throws {
        let url = Bundle.module.url(forResource: "agent-exit-codex", withExtension: "txt")!
        let text = try String(contentsOf: url, encoding: .utf8)
        let pattern = AgentKind.codex.defaultResumeRegex!
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        #expect(regex.firstMatch(in: text, range: range) != nil)
    }

    @Test
    func geminiAndOpenCodeReturnNil() {
        #expect(AgentKind.geminiCli.defaultResumeRegex == nil)
        #expect(AgentKind.openCode.defaultResumeRegex == nil)
        #expect(AgentKind.terminal.defaultResumeRegex == nil)
    }

    @Test
    func expectedBinaryNames() {
        #expect(AgentKind.claudeCode.expectedBinaryName == "claude")
        #expect(AgentKind.codex.expectedBinaryName == "codex")
        #expect(AgentKind.geminiCli.expectedBinaryName == "gemini")
        #expect(AgentKind.openCode.expectedBinaryName == "opencode")
        #expect(AgentKind.terminal.expectedBinaryName == nil)
    }
}
```

The regex strings used in the tests come from the validation notes file you produced in Phase 0.

- [ ] **Step 2: Run the test to confirm it fails**

```bash
swift test --filter RoostTests.AgentKindResumeTests
```

Expected: build error or failure (`defaultResumeRegex` and `expectedBinaryName` do not exist yet).

- [ ] **Step 3: Add the metadata to `AgentKind`**

Open `MuxyShared/Agent/AgentKind.swift` and add the following extension at the end of the file (use the regex strings you recorded in Phase 0; the values below are placeholders to be replaced by your fixture-confirmed regexes):

```swift
public extension AgentKind {
    var defaultResumeRegex: String? {
        switch self {
        case .claudeCode:
            return #"(?m)^\s*claude\s+--resume\s+\S+.*$"#
        case .codex:
            return #"(?m)^\s*codex\s+resume\s+\S+.*$"#
        case .geminiCli, .openCode, .terminal:
            return nil
        }
    }

    var expectedBinaryName: String? {
        switch self {
        case .claudeCode: return "claude"
        case .codex:      return "codex"
        case .geminiCli:  return "gemini"
        case .openCode:   return "opencode"
        case .terminal:   return nil
        }
    }
}
```

If your Phase 0 fixtures show the real regex needs to be different (for example because Claude prints `Resume with: claude --resume <id>` and the regex must anchor on `Resume with:`), update the regex strings before running the tests.

- [ ] **Step 4: Make sure fixtures are bundled into the test target**

Open `Package.swift` and ensure the `RoostTests` target has a `resources:` declaration pointing at `Tests/MuxyTests/Fixtures` (process or copy). If absent, add:

```swift
.testTarget(
    name: "RoostTests",
    dependencies: [...],
    path: "Tests/MuxyTests",
    resources: [.process("Fixtures")]
),
```

- [ ] **Step 5: Run the tests**

```bash
swift test --filter RoostTests.AgentKindResumeTests
```

Expected: PASS for all four cases.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(agent): add AgentKind defaultResumeRegex and expectedBinaryName"
```

## Task 1.2: Add `AgentKind.resumeStrategy`

**Files:**
- Modify: `MuxyShared/Agent/AgentKind.swift`
- Modify: `Tests/MuxyTests/Agent/AgentKindResumeTests.swift`

- [ ] **Step 1: Add the failing test cases**

Append to `AgentKindResumeTests.swift`:

```swift
extension AgentKindResumeTests {
    @Test
    func resumeStrategyByKind() {
        #expect(AgentKind.claudeCode.resumeStrategy == .appendArgs)
        #expect(AgentKind.codex.resumeStrategy == .replaceWithCaptured)
        #expect(AgentKind.geminiCli.resumeStrategy == .notSupported)
        #expect(AgentKind.openCode.resumeStrategy == .notSupported)
        #expect(AgentKind.terminal.resumeStrategy == .notSupported)
    }
}
```

- [ ] **Step 2: Run the test**

```bash
swift test --filter RoostTests.AgentKindResumeTests
```

Expected: build error (`ResumeStrategy` and `resumeStrategy` do not exist yet).

- [ ] **Step 3: Implement**

Open `MuxyShared/Agent/AgentKind.swift` and add:

```swift
public enum ResumeStrategy: Sendable, Hashable {
    case appendArgs
    case replaceWithCaptured
    case notSupported
}

public extension AgentKind {
    var resumeStrategy: ResumeStrategy {
        switch self {
        case .claudeCode: return .appendArgs
        case .codex:      return .replaceWithCaptured
        case .geminiCli, .openCode, .terminal: return .notSupported
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.AgentKindResumeTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(agent): add AgentKind.resumeStrategy"
```

## Task 1.3: Add `resumeCommandRegex` to `RoostConfigAgentPreset`

**Files:**
- Modify: `MuxyShared/Config/RoostConfig.swift`
- Modify: `Tests/MuxyTests/Config/RoostConfigTests.swift` (or create if absent)

- [ ] **Step 1: Write the failing test**

Add to `RoostConfigTests.swift` (create the file if it does not exist):

```swift
@Test
func decodesResumeCommandRegex() throws {
    let json = """
    {
        "name": "Custom Claude",
        "kind": "claudeCode",
        "command": "claude --foo",
        "resumeCommandRegex": "(?m)^claude --continue$"
    }
    """.data(using: .utf8)!
    let preset = try JSONDecoder().decode(RoostConfigAgentPreset.self, from: json)
    #expect(preset.resumeCommandRegex == "(?m)^claude --continue$")
}

@Test
func resumeCommandRegexIsOptional() throws {
    let json = """
    { "name": "X", "kind": "claudeCode", "command": "claude" }
    """.data(using: .utf8)!
    let preset = try JSONDecoder().decode(RoostConfigAgentPreset.self, from: json)
    #expect(preset.resumeCommandRegex == nil)
}
```

- [ ] **Step 2: Run test, see failure**

```bash
swift test --filter RoostTests.RoostConfigTests
```

Expected: failure (field does not exist).

- [ ] **Step 3: Add the field**

Open `MuxyShared/Config/RoostConfig.swift`. In `RoostConfigAgentPreset`:

1. Add field:

```swift
public let resumeCommandRegex: String?
```

2. Update `init`:

```swift
public init(
    name: String,
    kind: AgentKind,
    command: String?,
    env: [String: String] = [:],
    keychainEnv: [String: RoostConfigKeychainEnv] = [:],
    cardinality: RoostConfigCardinality = .shared,
    resumeCommandRegex: String? = nil
) {
    self.name = name
    self.kind = kind
    self.command = command
    self.env = env
    self.keychainEnv = keychainEnv
    self.cardinality = cardinality
    self.resumeCommandRegex = resumeCommandRegex
}
```

3. Update `CodingKeys`:

```swift
private enum CodingKeys: String, CodingKey {
    case name
    case kind
    case command
    case env
    case cardinality
    case resumeCommandRegex
}
```

4. Update `RoostConfigAgentPresetTolerant` similarly so the lenient decoder also picks up the field:

```swift
private struct RoostConfigAgentPresetTolerant: Decodable {
    let name: String
    let kind: AgentKind
    let command: String?
    let env: [String: String]?
    let keychainEnv: [String: RoostConfigKeychainEnv]?
    let cardinality: RoostConfigCardinality?
    let resumeCommandRegex: String?
}
```

And wherever the tolerant struct is converted to `RoostConfigAgentPreset`, pass the new field through.

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.RoostConfigTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(config): add resumeCommandRegex to RoostConfigAgentPreset"
```

## Task 1.4: Thread `resumeCommandRegex` through `AgentPreset` + catalog

**Files:**
- Modify: `MuxyShared/Agent/AgentPreset.swift`
- Create: `Tests/MuxyTests/Agent/AgentPresetCatalogTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MuxyTests/Agent/AgentPresetCatalogTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@Suite("AgentPresetCatalog resume regex")
struct AgentPresetCatalogResumeTests {
    @Test
    func builtInPresetsHaveNilOverride() {
        #expect(AgentPresetCatalog.preset(for: .claudeCode).resumeCommandRegex == nil)
        #expect(AgentPresetCatalog.preset(for: .codex).resumeCommandRegex == nil)
    }

    @Test
    func configuredOverrideThreadsThrough() {
        let configured = [
            RoostConfigAgentPreset(
                name: "X",
                kind: .claudeCode,
                command: "claude --foo",
                resumeCommandRegex: "(?m)^claude --continue$"
            )
        ]
        let preset = AgentPresetCatalog.preset(
            for: .claudeCode,
            env: [:],
            configuredPresets: configured
        )
        #expect(preset.resumeCommandRegex == "(?m)^claude --continue$")
        #expect(preset.defaultCommand == "claude --foo")
    }
}
```

- [ ] **Step 2: Run test, see failure**

```bash
swift test --filter RoostTests.AgentPresetCatalogResumeTests
```

Expected: build error (`resumeCommandRegex` does not exist on `AgentPreset`).

- [ ] **Step 3: Update `AgentPreset` and the catalog**

Open `MuxyShared/Agent/AgentPreset.swift`. Replace the struct and catalog with:

```swift
import Foundation

public struct AgentPreset: Sendable, Hashable {
    public let kind: AgentKind
    public let defaultCommand: String?
    public let env: [String: String]
    public let requiresDedicatedWorkspace: Bool
    public let resumeCommandRegex: String?

    public init(
        kind: AgentKind,
        defaultCommand: String?,
        env: [String: String] = [:],
        requiresDedicatedWorkspace: Bool = false,
        resumeCommandRegex: String? = nil
    ) {
        self.kind = kind
        self.defaultCommand = defaultCommand
        self.env = env
        self.requiresDedicatedWorkspace = requiresDedicatedWorkspace
        self.resumeCommandRegex = resumeCommandRegex
    }
}

public enum AgentPresetCatalog {
    public static func preset(for kind: AgentKind) -> AgentPreset {
        builtIn(for: kind)
    }

    public static func preset(
        for kind: AgentKind,
        env: [String: String] = [:],
        configuredPresets: [RoostConfigAgentPreset]
    ) -> AgentPreset {
        if let override = configuredPresets.first(where: { $0.kind == kind }) {
            return AgentPreset(
                kind: kind,
                defaultCommand: override.command,
                env: env.merging(override.env) { _, override in override },
                requiresDedicatedWorkspace: override.cardinality == .dedicated,
                resumeCommandRegex: override.resumeCommandRegex
            )
        }
        let preset = builtIn(for: kind)
        return AgentPreset(
            kind: preset.kind,
            defaultCommand: preset.defaultCommand,
            env: preset.env.merging(env) { _, override in override },
            requiresDedicatedWorkspace: preset.requiresDedicatedWorkspace,
            resumeCommandRegex: preset.resumeCommandRegex
        )
    }

    private static func builtIn(for kind: AgentKind) -> AgentPreset {
        switch kind {
        case .terminal:
            AgentPreset(kind: .terminal, defaultCommand: nil)
        case .claudeCode:
            AgentPreset(kind: .claudeCode, defaultCommand: "claude --dangerously-skip-permissions")
        case .codex:
            AgentPreset(kind: .codex, defaultCommand: "codex --disable apps --dangerously-bypass-approvals-and-sandbox")
        case .geminiCli:
            AgentPreset(kind: .geminiCli, defaultCommand: "gemini --yolo")
        case .openCode:
            AgentPreset(
                kind: .openCode,
                defaultCommand: "opencode",
                env: ["OPENCODE_PERMISSION": "{\"*\":\"allow\"}"]
            )
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.AgentPresetCatalogResumeTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(agent): thread resumeCommandRegex through AgentPreset and catalog"
```

## Task 1.5: Add new fields to `TerminalPaneState`

**Files:**
- Modify: `Muxy/Models/TerminalPaneState.swift`
- Modify: `Tests/MuxyTests/Models/TerminalPaneStateTests.swift` (create if absent)

- [ ] **Step 1: Write the failing test**

Add a test that verifies the default values:

```swift
@Test
func newReloadFieldsDefaultToCleanState() {
    let state = TerminalPaneState(/* existing minimum init */)
    #expect(state.capturedResumeCommand == nil)
    #expect(state.agentBinaryPath == nil)
    #expect(state.agentBinaryMTime == nil)
    #expect(state.binaryUpdateDetected == false)
    #expect(state.exitBannerDismissed == false)
    #expect(state.mtimeBannerDismissed == false)
}
```

(Match the existing test file's style. If `TerminalPaneStateTests.swift` does not exist, copy the imports + Suite header from a sibling tests file.)

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.TerminalPaneStateTests
```

Expected: build error.

- [ ] **Step 3: Add fields**

Open `Muxy/Models/TerminalPaneState.swift`. Inside the `final class TerminalPaneState`, add (placement: with the other mutable state fields):

```swift
var sessionID: UUID
var capturedResumeCommand: String?
var agentBinaryPath: URL?
var agentBinaryMTime: Date?
var binaryUpdateDetected: Bool = false
var exitBannerDismissed: Bool = false
var mtimeBannerDismissed: Bool = false
```

In the designated initializer, add a `sessionID: UUID = UUID()` parameter and assign it; existing call sites pass the session id when known (search for `TerminalPaneState(` and update the most recent ones — typically inside `AppState.createSession` and snapshot restore).

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.TerminalPaneStateTests
```

Expected: PASS.

- [ ] **Step 5: Update existing call sites that construct `TerminalPaneState`**

Search the project:

```bash
rg -n 'TerminalPaneState\(' Muxy MuxyServer Tests
```

For each hit, decide whether to pass `sessionID:` explicitly. Production paths that have a `SessionRecord` available pass the record's id; tests can rely on the default.

- [ ] **Step 6: Build**

```bash
swift build
```

Expected: SUCCESS.

- [ ] **Step 7: Commit**

```bash
jj commit -m "feat(pane): add reload-related fields to TerminalPaneState"
```

## Task 1.6: Persist `sessionID` in `TerminalTabSnapshot`

**Files:**
- Modify: `Muxy/Models/WorkspaceSnapshot.swift`
- Modify: `Muxy/Models/TerminalTab.swift`
- Modify: existing snapshot tests (search for `TerminalTabSnapshot`)

- [ ] **Step 1: Write the failing test**

Find an existing test that round-trips a `WorkspaceSnapshot` through JSON. Add an assertion that `tab.sessionID` survives the round trip. If no test exists, create one in `Tests/MuxyTests/Models/WorkspaceSnapshotRoundTripTests.swift`:

```swift
@Test
func tabSessionIDSurvivesEncodeDecode() throws {
    let snap = TerminalTabSnapshot(
        // fill required fields, set sessionID to a known UUID
    )
    let data = try JSONEncoder().encode(snap)
    let decoded = try JSONDecoder().decode(TerminalTabSnapshot.self, from: data)
    #expect(decoded.sessionID == snap.sessionID)
}
```

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.WorkspaceSnapshotRoundTripTests
```

Expected: failure (field absent).

- [ ] **Step 3: Add `sessionID: UUID?` to `TerminalTabSnapshot`**

Open `Muxy/Models/WorkspaceSnapshot.swift` and add:

```swift
struct TerminalTabSnapshot: Codable {
    // existing fields...
    let sessionID: UUID?

    // existing init unchanged; add sessionID parameter at the end with `nil` default
}
```

Make sure decoding tolerates missing field (Codable handles `Optional?` with `decodeIfPresent` automatically when manually implementing CodingKeys; if the struct uses synthesized Codable, `Optional?` of an encoded missing key does fail. Use a manual `init(from:)` if needed):

```swift
init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    // ... existing field decodes ...
    self.sessionID = try c.decodeIfPresent(UUID.self, forKey: .sessionID)
}
```

In `TerminalTab.swift`, update the snapshot factory at line 147 (`func snapshot()`) to pass `sessionID: paneState.sessionID`. Update the restore initializer at line 101 (`restoring snapshot:`) to read `snapshot.sessionID ?? UUID()` and feed it to `TerminalPaneState`.

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.WorkspaceSnapshotRoundTripTests
```

Expected: PASS.

- [ ] **Step 5: Run the broader snapshot suite**

```bash
swift test --filter RoostTests.Workspace
```

Expected: existing tests still PASS (sessionID is optional and defaults).

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(snapshot): persist pane sessionID in TerminalTabSnapshot"
```

## Task 1.7: Add `lastTail` column + migration in `SessionStore`

**Files:**
- Modify: `RoostHostdCore/SessionStore.swift`
- Modify: `RoostHostdCore/SessionRecord.swift`
- Create: `Tests/MuxyTests/Hostd/SessionStoreMigrationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MuxyTests/Hostd/SessionStoreMigrationTests.swift`:

```swift
import Foundation
@testable import RoostHostdCore
import Testing

@Suite("SessionStore migration v2")
struct SessionStoreMigrationTests {
    @Test
    func openDatabaseAddsLastTailColumn() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-test-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SessionStore(url: url)
        let record = SessionRecord(
            id: UUID(),
            // ...other required fields with synthetic values...
            lastTail: "captured tail line"
        )
        try store.record(record)
        let read = try store.fetchAll().first { $0.id == record.id }
        #expect(read?.lastTail == "captured tail line")
    }

    @Test
    func nilLastTailRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-test-\(UUID()).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SessionStore(url: url)
        let record = SessionRecord(
            id: UUID(),
            // ...
            lastTail: nil
        )
        try store.record(record)
        let read = try store.fetchAll().first { $0.id == record.id }
        #expect(read?.lastTail == nil)
    }
}
```

(Fill in the `// ...` placeholders by looking at the existing `SessionRecord` initializer.)

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.SessionStoreMigrationTests
```

Expected: build error.

- [ ] **Step 3: Add field to `SessionRecord`**

Open `RoostHostdCore/SessionRecord.swift`. Add:

```swift
public let lastTail: String?
```

Add `lastTail: String?` parameter (with `nil` default) to the initializer; assign in body.

- [ ] **Step 4: Add SQLite migration**

Open `RoostHostdCore/SessionStore.swift`. Find the place that opens the database and runs migrations (look for `user_version`). Add a v2 migration block:

```swift
let userVersion = try database.scalarInt("PRAGMA user_version") ?? 0
if userVersion < 2 {
    try database.execute("ALTER TABLE sessions ADD COLUMN last_tail TEXT")
    try database.execute("PRAGMA user_version = 2")
}
```

Update the SELECT and INSERT/UPSERT statements that hit `sessions` to read/write `last_tail`. The exact column ordinal depends on existing SQL; bind `record.lastTail` as a nullable text value.

- [ ] **Step 5: Run tests**

```bash
swift test --filter RoostTests.SessionStoreMigrationTests
```

Expected: PASS.

- [ ] **Step 6: Run the full hostd suite**

```bash
swift test --filter RoostTests.Hostd
```

Expected: PASS, no regressions.

- [ ] **Step 7: Commit**

```bash
jj commit -m "feat(hostd): persist captured agent tail in SessionRecord (schema v2)"
```

## Task 1.8: Bump protocol version + extend `HostdSessionExitNotice`

**Files:**
- Modify: `RoostHostdCore/HostdAttachSocketMessages.swift`
- Modify: `Tests/MuxyTests/Hostd/HostdDaemonRuntimeIdentityTests.swift`

- [ ] **Step 1: Update the failing test**

Open `HostdDaemonRuntimeIdentityTests.swift`. Change the hard-coded version expectation:

```swift
#expect(HostdDaemonRuntimeIdentity.currentProtocolVersion == 8)
```

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.HostdDaemonRuntimeIdentity
```

Expected: failure (still 7).

- [ ] **Step 3: Bump the constant and extend exit notice**

Open `RoostHostdCore/HostdAttachSocketMessages.swift`. In `HostdDaemonRuntimeIdentity`:

```swift
public static let currentProtocolVersion: Int = 8
```

Find `HostdSessionExitNotice` (or create if absent — search for the type that delivers exit events from daemon to app) and add:

```swift
public let lastTail: String?
```

Update the initializer and `Codable` keys accordingly. Use `decodeIfPresent` so older notices without the field still decode as `nil`.

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.Hostd
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(hostd): bump protocol to v8 and add lastTail to exit notice"
```

---

# Phase 2: Command Building

## Task 2.1: `AgentBinary.resolvePath`

**Files:**
- Create: `MuxyShared/Agent/AgentBinary.swift`
- Create: `Tests/MuxyTests/Agent/AgentBinaryTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MuxyTests/Agent/AgentBinaryTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@Suite("AgentBinary path resolution")
struct AgentBinaryResolvePathTests {
    @Test
    func absolutePathIsReturnedDirectly() {
        let path = AgentBinary.resolvePath(
            command: "/usr/local/bin/claude --foo",
            env: [:]
        )
        #expect(path?.path == "/usr/local/bin/claude")
    }

    @Test
    func usesPATHForBareName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bin = dir.appendingPathComponent("xclaude")
        try Data().write(to: bin)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        let path = AgentBinary.resolvePath(
            command: "xclaude --foo",
            env: ["PATH": dir.path]
        )
        #expect(path?.path == bin.path)
    }

    @Test
    func quotedAbsolutePathTokenized() {
        let path = AgentBinary.resolvePath(
            command: "\"/Applications/Claude.app/Contents/MacOS/claude\" --foo",
            env: [:]
        )
        #expect(path?.path == "/Applications/Claude.app/Contents/MacOS/claude")
    }

    @Test
    func unresolvableReturnsNil() {
        let path = AgentBinary.resolvePath(
            command: "definitely-not-a-real-binary-xyz123 --foo",
            env: ["PATH": "/dev/null/empty"]
        )
        #expect(path == nil)
    }
}
```

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.AgentBinaryResolvePathTests
```

Expected: build error.

- [ ] **Step 3: Implement**

Create `MuxyShared/Agent/AgentBinary.swift`:

```swift
import Foundation

public enum AgentBinary {
    public static func resolvePath(command: String, env: [String: String]) -> URL? {
        guard let firstToken = firstToken(in: command) else { return nil }
        if firstToken.hasPrefix("/") {
            return URL(fileURLWithPath: firstToken)
        }
        let pathEntries = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for entry in pathEntries where !entry.isEmpty {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent(firstToken)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public static func stripBinaryName(from command: String, kind: AgentKind) -> String? {
        guard let expected = kind.expectedBinaryName,
              let firstToken = firstToken(in: command)
        else { return nil }
        let trailingName = (firstToken as NSString).lastPathComponent
        guard trailingName == expected else { return nil }
        let after = command.drop { !$0.isWhitespace }
        return String(after).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstToken(in command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("\"") {
            let body = trimmed.dropFirst()
            if let close = body.firstIndex(of: "\"") {
                return String(body[..<close])
            }
        }
        return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.AgentBinaryResolvePathTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(agent): add AgentBinary.resolvePath"
```

## Task 2.2: `AgentBinary.stripBinaryName` tests

**Files:**
- Modify: `Tests/MuxyTests/Agent/AgentBinaryTests.swift`

- [ ] **Step 1: Add tests**

Append to `AgentBinaryTests.swift`:

```swift
@Suite("AgentBinary.stripBinaryName")
struct AgentBinaryStripTests {
    @Test
    func claudeStripsLeadingBinary() {
        let result = AgentBinary.stripBinaryName(
            from: "claude --resume abc-123",
            kind: .claudeCode
        )
        #expect(result == "--resume abc-123")
    }

    @Test
    func absolutePathBinaryIsStripped() {
        let result = AgentBinary.stripBinaryName(
            from: "/usr/local/bin/claude --resume abc",
            kind: .claudeCode
        )
        #expect(result == "--resume abc")
    }

    @Test
    func mismatchedBinaryReturnsNil() {
        let result = AgentBinary.stripBinaryName(
            from: "rogue --resume abc",
            kind: .claudeCode
        )
        #expect(result == nil)
    }

    @Test
    func emptyCommandReturnsNil() {
        let result = AgentBinary.stripBinaryName(from: "", kind: .claudeCode)
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Run tests**

```bash
swift test --filter RoostTests.AgentBinaryStripTests
```

Expected: PASS (implementation already shipped in Task 2.1; this task formalizes the contract).

- [ ] **Step 3: Commit**

```bash
jj commit -m "test(agent): cover AgentBinary.stripBinaryName edge cases"
```

## Task 2.3: `ResumeArgs` validators

**Files:**
- Create: `MuxyShared/Agent/ResumeArgs.swift`
- Create: `Tests/MuxyTests/Agent/ResumeArgsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MuxyTests/Agent/ResumeArgsTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@Suite("ResumeArgs metacharacter check")
struct ResumeArgsTests {
    @Test
    func plainArgsAccepted() {
        #expect(!ResumeArgs.containsShellMetacharacters("--resume abc-123"))
    }

    @Test
    func semicolonRejected() {
        #expect(ResumeArgs.containsShellMetacharacters("--resume abc; rm -rf /"))
    }

    @Test
    func pipeRejected() {
        #expect(ResumeArgs.containsShellMetacharacters("--resume abc | tee"))
    }

    @Test
    func backtickRejected() {
        #expect(ResumeArgs.containsShellMetacharacters("--resume `whoami`"))
    }

    @Test
    func dollarParenRejected() {
        #expect(ResumeArgs.containsShellMetacharacters("--resume $(date)"))
    }

    @Test
    func newlineRejected() {
        #expect(ResumeArgs.containsShellMetacharacters("--resume abc\nls"))
    }

    @Test
    func redirectsRejected() {
        #expect(ResumeArgs.containsShellMetacharacters("--resume abc > /tmp/x"))
        #expect(ResumeArgs.containsShellMetacharacters("--resume abc < /tmp/x"))
    }

    @Test
    func captureLooksValidForCodex() {
        #expect(ResumeArgs.captureLooksValid("codex resume abc-123", kind: .codex))
        #expect(!ResumeArgs.captureLooksValid("rogue resume abc", kind: .codex))
        #expect(!ResumeArgs.captureLooksValid("codex resume `evil`", kind: .codex))
    }
}
```

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.ResumeArgsTests
```

Expected: build error.

- [ ] **Step 3: Implement**

Create `MuxyShared/Agent/ResumeArgs.swift`:

```swift
import Foundation

public enum ResumeArgs {
    public static func containsShellMetacharacters(_ s: String) -> Bool {
        let bad: [Character] = [";", "|", "&", "`", "\n", "\r", ">", "<"]
        if s.contains("$(") { return true }
        for ch in s where bad.contains(ch) { return true }
        return false
    }

    public static func captureLooksValid(_ captured: String, kind: AgentKind) -> Bool {
        guard let expected = kind.expectedBinaryName else { return false }
        let firstToken = AgentBinary.firstToken(in: captured) ?? ""
        let trailing = (firstToken as NSString).lastPathComponent
        guard trailing == expected else { return false }
        return !containsShellMetacharacters(captured)
    }
}
```

`AgentBinary.firstToken` is currently `internal`; make it `public` (or move the helper into a shared file) so `ResumeArgs` can call it.

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.ResumeArgsTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(agent): add ResumeArgs metacharacter and capture validators"
```

## Task 2.4: `AgentReloadCommandBuilder.build`

**Files:**
- Create: `MuxyShared/Agent/AgentReloadCommandBuilder.swift`
- Create: `Tests/MuxyTests/Agent/AgentReloadCommandBuilderTests.swift`
- Create: `MuxyShared/Agent/AgentReloadMode.swift` (small enum)

- [ ] **Step 1: Add the mode enum**

Create `MuxyShared/Agent/AgentReloadMode.swift`:

```swift
import Foundation

public enum AgentReloadMode: Sendable, Hashable, Codable {
    case resume
    case fresh
}
```

- [ ] **Step 2: Write the failing test**

Create `Tests/MuxyTests/Agent/AgentReloadCommandBuilderTests.swift`:

```swift
import Foundation
import MuxyShared
import Testing

@Suite("AgentReloadCommandBuilder")
struct AgentReloadCommandBuilderTests {
    @Test
    func freshAlwaysReturnsDefaultCommand() {
        let preset = AgentPreset(
            kind: .claudeCode,
            defaultCommand: "claude --x",
            resumeCommandRegex: nil
        )
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "claude --resume abc",
            mode: .fresh
        )
        #expect(cmd == "claude --x")
    }

    @Test
    func claudeAppendArgs() {
        let preset = AgentPreset(kind: .claudeCode, defaultCommand: "claude --x")
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "claude --resume abc",
            mode: .resume
        )
        #expect(cmd == "claude --x --resume abc")
    }

    @Test
    func claudeMismatchedCaptureFallsBackToDefault() {
        let preset = AgentPreset(kind: .claudeCode, defaultCommand: "claude --x")
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "rogue --resume abc",
            mode: .resume
        )
        #expect(cmd == "claude --x")
    }

    @Test
    func claudeMetacharCaptureFallsBackToDefault() {
        let preset = AgentPreset(kind: .claudeCode, defaultCommand: "claude --x")
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "claude --resume abc; ls",
            mode: .resume
        )
        #expect(cmd == "claude --x")
    }

    @Test
    func codexUsesCapturedVerbatim() {
        let preset = AgentPreset(kind: .codex, defaultCommand: "codex --y")
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "codex resume abc-123",
            mode: .resume
        )
        #expect(cmd == "codex resume abc-123")
    }

    @Test
    func codexInvalidCapturedFallsBackToDefault() {
        let preset = AgentPreset(kind: .codex, defaultCommand: "codex --y")
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "rogue resume abc",
            mode: .resume
        )
        #expect(cmd == "codex --y")
    }

    @Test
    func notSupportedFallsBackToDefault() {
        let preset = AgentPreset(kind: .geminiCli, defaultCommand: "gemini --z")
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: "anything",
            mode: .resume
        )
        #expect(cmd == "gemini --z")
    }

    @Test
    func nilDefaultCommandPropagatesAsEmpty() {
        let preset = AgentPreset(kind: .terminal, defaultCommand: nil)
        let cmd = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: nil,
            mode: .fresh
        )
        #expect(cmd == "")
    }
}
```

- [ ] **Step 3: Run, see failure**

```bash
swift test --filter RoostTests.AgentReloadCommandBuilderTests
```

Expected: build error.

- [ ] **Step 4: Implement**

Create `MuxyShared/Agent/AgentReloadCommandBuilder.swift`:

```swift
import Foundation

public enum AgentReloadCommandBuilder {
    public static func build(
        preset: AgentPreset,
        captured: String?,
        mode: AgentReloadMode
    ) -> String {
        let base = preset.defaultCommand ?? ""
        guard mode == .resume, let captured else { return base }
        switch preset.kind.resumeStrategy {
        case .notSupported:
            return base
        case .replaceWithCaptured:
            guard ResumeArgs.captureLooksValid(captured, kind: preset.kind) else {
                return base
            }
            return captured
        case .appendArgs:
            guard let args = AgentBinary.stripBinaryName(from: captured, kind: preset.kind),
                  !ResumeArgs.containsShellMetacharacters(args)
            else { return base }
            return "\(base) \(args)"
        }
    }
}
```

- [ ] **Step 5: Run tests**

```bash
swift test --filter RoostTests.AgentReloadCommandBuilderTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(agent): add AgentReloadCommandBuilder with per-strategy logic"
```

---

# Phase 3: Tmux Capture

## Task 3.1: Extend `HostdTmuxControlling` protocol

**Files:**
- Modify: `RoostHostdCore/HostdTmuxSession.swift`
- Modify: existing tests that mock `HostdTmuxControlling` (search `HostdTmuxControlling`)

- [ ] **Step 1: Add the new protocol methods**

Open `RoostHostdCore/HostdTmuxSession.swift`. Update the protocol:

```swift
public protocol HostdTmuxControlling: Sendable {
    func launch(
        sessionName: String,
        workspacePath: String,
        command: String,
        environment: [String: String]
    ) async throws
    func hasSession(named sessionName: String) async -> Bool
    func killSession(named sessionName: String) async throws

    func isPaneDead(sessionName: String) async -> Bool
    func captureLastTail(sessionName: String, lines: Int) async -> String?
    func sendKeys(sessionName: String, keys: String) async throws
}
```

- [ ] **Step 2: Update existing mocks to implement no-op defaults**

Search:

```bash
rg -n 'HostdTmuxControlling' Tests
```

For each mock that conforms to `HostdTmuxControlling`, add stub implementations that record calls or return safe defaults (e.g. `isPaneDead` returns `false`, `captureLastTail` returns `nil`, `sendKeys` is a no-op or records the call). This keeps existing tests compiling.

- [ ] **Step 3: Build**

```bash
swift build
```

Expected: SUCCESS.

- [ ] **Step 4: Commit**

```bash
jj commit -m "refactor(hostd): extend HostdTmuxControlling with capture and send-keys"
```

## Task 3.2: Add `remain-on-exit on` to launch arguments

**Files:**
- Modify: `RoostHostdCore/HostdTmuxSession.swift`
- Modify: `Tests/MuxyTests/Terminal/TerminalPaneEnvironmentTests.swift`

- [ ] **Step 1: Update the test for launch arguments**

Find the existing test that snapshots `HostdTmuxController.launchArguments` (it lives near `attach-session -t roost-...` assertions). Add an assertion that the argument list contains the literal sequence `"set-option", "-t", "<sessionName>", "remain-on-exit", "on"`:

```swift
@Test
func launchArgumentsIncludeRemainOnExit() {
    let args = HostdTmuxController.launchArguments(
        sessionName: "roost-X",
        workspacePath: "/tmp",
        command: "/bin/true",
        environment: [:]
    )
    let zipped = zip(args.dropLast(), args.dropFirst()).map { ($0, $1) }
    let pairs = stride(from: 0, to: args.count - 4, by: 1).contains { i in
        args[i] == ";"
            && args[i+1] == "set-option"
            && args[i+2] == "-t"
            && args[i+3] == "roost-X"
            && args[i+4] == "remain-on-exit"
            && (i+5 < args.count) && args[i+5] == "on"
    }
    #expect(pairs)
    _ = zipped // keep helper
}
```

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.TerminalPaneEnvironmentTests
```

Expected: failure.

- [ ] **Step 3: Add the option to `roostSessionOptionArguments`**

In `HostdTmuxSession.swift`, find `roostSessionOptionArguments` (line ~160). Append before the `bind-key -T root WheelUpPane` entry (or near the other `set-option -t sessionName` entries):

```swift
";", "set-option", "-t", sessionName, "remain-on-exit", "on",
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.TerminalPaneEnvironmentTests
```

Expected: PASS, plus existing assertions still PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(hostd): set tmux remain-on-exit on for Roost-owned sessions"
```

## Task 3.3: Implement `isPaneDead` and `captureLastTail`

**Files:**
- Modify: `RoostHostdCore/HostdTmuxSession.swift`
- Create: `Tests/MuxyTests/Hostd/HostdTmuxControllerCaptureTests.swift`

- [ ] **Step 1: Write the failing integration test**

Create `Tests/MuxyTests/Hostd/HostdTmuxControllerCaptureTests.swift`:

```swift
import Foundation
@testable import RoostHostdCore
import Testing

@Suite("HostdTmuxController capture", .enabled(if: tmuxAvailable()))
struct HostdTmuxControllerCaptureTests {
    @Test
    func paneDeadAndCaptureAfterAgentExit() async throws {
        let controller = HostdTmuxController()
        let name = "roost-test-cap-\(UUID().uuidString.prefix(8))"
        try await controller.launch(
            sessionName: name,
            workspacePath: "/tmp",
            command: "echo TAIL_MARKER_xyzzy && exit 0",
            environment: [:]
        )
        // Wait up to 2 s for the pane to become dead.
        var dead = false
        for _ in 0..<20 {
            if await controller.isPaneDead(sessionName: name) { dead = true; break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(dead)
        let tail = await controller.captureLastTail(sessionName: name, lines: 50)
        try? await controller.killSession(named: name)
        #expect(tail?.contains("TAIL_MARKER_xyzzy") == true)
    }
}

private func tmuxAvailable() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["tmux", "-V"]
    p.standardOutput = Pipe()
    p.standardError = Pipe()
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
}
```

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.HostdTmuxControllerCaptureTests
```

Expected: build error or failure (methods do not exist).

- [ ] **Step 3: Implement both methods**

Open `RoostHostdCore/HostdTmuxSession.swift`. Add to `HostdTmuxController`:

```swift
public func isPaneDead(sessionName: String) async -> Bool {
    let r = try? await run(
        arguments: ["list-panes", "-t", sessionName, "-F", "#{pane_dead}"],
        environment: [:]
    )
    return r?.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
}

public func captureLastTail(sessionName: String, lines: Int) async -> String? {
    let target = "\(sessionName):0.0"
    let r = try? await run(
        arguments: ["capture-pane", "-t", target, "-p", "-S", "-\(lines)", "-N", "-J"],
        environment: [:]
    )
    guard let r, r.status == 0 else { return nil }
    return Self.stripPaneDeadMarker(r.output)
}

public func sendKeys(sessionName: String, keys: String) async throws {
    let r = try await run(
        arguments: ["send-keys", "-t", sessionName, keys],
        environment: [:]
    )
    guard r.status == 0 else {
        throw HostdProcessRegistryError.tmuxCommandFailed(
            operation: "send-keys",
            status: r.status,
            message: r.errorMessage
        )
    }
}

static func stripPaneDeadMarker(_ s: String) -> String {
    s.split(whereSeparator: \.isNewline)
        .filter { !$0.contains("Pane is dead") }
        .joined(separator: "\n")
}
```

(If your Phase 0.3 validation showed `-J` is unnecessary, drop it from the `captureLastTail` arguments; otherwise keep it so wrapped lines are joined.)

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.HostdTmuxControllerCaptureTests
```

Expected: PASS (skipped if `tmux` is missing).

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(hostd): implement tmux isPaneDead, captureLastTail, sendKeys"
```

## Task 3.4: Add `startTmuxExitWatcher` and wire into `launchTmuxSession`

**Files:**
- Modify: `RoostHostdCore/HostdProcessRegistry.swift`
- Create: `Tests/MuxyTests/Hostd/TmuxExitWatcherTests.swift`

- [ ] **Step 1: Write the failing test using a mock `HostdTmuxControlling`**

Create `Tests/MuxyTests/Hostd/TmuxExitWatcherTests.swift`:

```swift
import Foundation
@testable import RoostHostdCore
import Testing

@Suite("Tmux exit watcher")
struct TmuxExitWatcherTests {
    final class MockTmux: HostdTmuxControlling, @unchecked Sendable {
        var hasSessionResults: [Bool]
        var paneDeadResults: [Bool]
        var lastTailValue: String?
        var killCount = 0

        init(hasSession: [Bool], paneDead: [Bool], lastTail: String?) {
            self.hasSessionResults = hasSession
            self.paneDeadResults = paneDead
            self.lastTailValue = lastTail
        }

        func launch(sessionName: String, workspacePath: String, command: String, environment: [String: String]) async throws {}
        func hasSession(named sessionName: String) async -> Bool {
            hasSessionResults.isEmpty ? false : hasSessionResults.removeFirst()
        }
        func killSession(named sessionName: String) async throws { killCount += 1 }
        func isPaneDead(sessionName: String) async -> Bool {
            paneDeadResults.isEmpty ? false : paneDeadResults.removeFirst()
        }
        func captureLastTail(sessionName: String, lines: Int) async -> String? { lastTailValue }
        func sendKeys(sessionName: String, keys: String) async throws {}
    }

    @Test
    func reportsExitWithCapturedTail() async {
        let mock = MockTmux(
            hasSession: [true, true, true],
            paneDead: [false, false, true],
            lastTail: "TAIL_MARKER"
        )
        var captured: String? = nil
        var exited = false
        await HostdProcessRegistry.runTmuxExitWatcherLoop(
            sessionName: "roost-X",
            tmux: mock,
            pollNanoseconds: 50_000_000
        ) { tail in
            captured = tail
            exited = true
        }
        #expect(exited)
        #expect(captured == "TAIL_MARKER")
        #expect(mock.killCount == 1)
    }

    @Test
    func sessionLostReportsNilTail() async {
        let mock = MockTmux(
            hasSession: [false],
            paneDead: [],
            lastTail: nil
        )
        var captured: String? = "not-changed"
        var exited = false
        await HostdProcessRegistry.runTmuxExitWatcherLoop(
            sessionName: "roost-X",
            tmux: mock,
            pollNanoseconds: 50_000_000
        ) { tail in
            captured = tail
            exited = true
        }
        #expect(exited)
        #expect(captured == nil)
        #expect(mock.killCount == 0)
    }
}
```

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.TmuxExitWatcherTests
```

Expected: build error.

- [ ] **Step 3: Implement `startTmuxExitWatcher`**

Open `RoostHostdCore/HostdProcessRegistry.swift`. Add:

```swift
private static let paneDeadPollNanoseconds: UInt64 = 500_000_000

internal static func runTmuxExitWatcherLoop(
    sessionName: String,
    tmux: any HostdTmuxControlling,
    pollNanoseconds: UInt64 = HostdProcessRegistry.paneDeadPollNanoseconds,
    onExit: @Sendable @escaping (_ lastTail: String?) -> Void
) async {
    while !Task.isCancelled {
        if !(await tmux.hasSession(named: sessionName)) {
            onExit(nil)
            return
        }
        if await tmux.isPaneDead(sessionName: sessionName) {
            let tail = await tmux.captureLastTail(sessionName: sessionName, lines: 200)
            onExit(tail)
            try? await tmux.killSession(named: sessionName)
            return
        }
        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }
}

private func startTmuxExitWatcher(id: UUID, sessionName: String) {
    Task { [weak self] in
        await Self.runTmuxExitWatcherLoop(
            sessionName: sessionName,
            tmux: self?.tmux ?? HostdTmuxController()
        ) { [weak self] lastTail in
            await self?.handleTmuxExit(id: id, sessionName: sessionName, lastTail: lastTail)
        }
    }
}

private func handleTmuxExit(id: UUID, sessionName: String, lastTail: String?) async {
    if let store = sessionStore, let existing = try? store.fetch(id: id) {
        let updated = SessionRecord(
            id: existing.id,
            agentKind: existing.agentKind,
            command: existing.command,
            workspacePath: existing.workspacePath,
            createdAt: existing.createdAt,
            lastState: .exited,
            lastTail: lastTail
        )
        try? store.record(updated)
    }
    sessionExitContinuation?.yield(
        HostdSessionExitNotice(id: id, lastTail: lastTail)
    )
    sessions.removeValue(forKey: id)
    tmuxAttachedClientCounts.removeValue(forKey: id)
}
```

(Adapt the field names and access modifiers to match the existing actor / class style of `HostdProcessRegistry`. The exact persistence / continuation hooks depend on existing helpers — search the file for how PTY exits are emitted today and mirror that path.)

- [ ] **Step 4: Wire into `launchTmuxSession`**

In the same file, find `launchTmuxSession` (line ~293). Right after a successful `try await tmux.launch(...)`, add:

```swift
let sessionName = HostdTmuxSessionName.name(for: id)
startTmuxExitWatcher(id: id, sessionName: sessionName)
```

- [ ] **Step 5: Run tests**

```bash
swift test --filter RoostTests.TmuxExitWatcherTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(hostd): add startTmuxExitWatcher and wire into tmux launch path"
```

---

# Phase 4: Client API (interruptSession)

## Task 4.1: Add `interruptSession` to the protocol and `LocalHostdClient`

**Files:**
- Modify: `Muxy/Services/Hostd/RoostHostdClient.swift`

- [ ] **Step 1: Extend the protocol**

In `RoostHostdClient.swift`, add the method to the `RoostHostdClient` protocol:

```swift
func interruptSession(id: UUID) async throws
```

- [ ] **Step 2: Provide a default implementation that throws**

```swift
extension RoostHostdClient {
    func interruptSession(id: UUID) async throws {
        throw RoostHostdClientError.unsupported(
            operation: "interruptSession"
        )
    }
}
```

(The default ensures compile-time safety while we land the real implementations.)

- [ ] **Step 3: Implement on `LocalHostdClient`**

In the same file, add to `LocalHostdClient`:

```swift
func interruptSession(id: UUID) async throws {
    let sessionName = HostdTmuxSessionName.name(for: id)
    try await registry.tmux.sendKeys(sessionName: sessionName, keys: "C-c")
}
```

(Adjust property accessors to match how `LocalHostdClient` reaches the registry / tmux today.)

- [ ] **Step 4: Build**

```bash
swift build
```

Expected: SUCCESS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(hostd-client): add interruptSession to RoostHostdClient + LocalHostdClient"
```

## Task 4.2: Implement `interruptSession` over the daemon socket

**Files:**
- Modify: `RoostHostdCore/HostdAttachSocketMessages.swift`
- Modify: `RoostHostdCore/HostdDaemonSocketServer.swift`
- Modify: `Muxy/Services/Hostd/HostdSocketTransport.swift`
- Modify: `Muxy/Services/Hostd/XPCHostdClient.swift`

- [ ] **Step 1: Define the request type**

In `HostdAttachSocketMessages.swift`:

```swift
public struct HostdInterruptSessionRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public init(id: UUID) { self.id = id }
}
```

Add a new case to the message-route enum (search for the place that lists `terminateSession`, `sendSessionSignal`, etc.) called `interruptSession`.

- [ ] **Step 2: Route on the daemon side**

In `HostdDaemonSocketServer.swift`, in the routing switch that handles `terminateSession` etc., add:

```swift
case .interruptSession:
    let req = try HostdXPCCodec.decode(HostdInterruptSessionRequest.self, from: payload)
    try await registry.interruptTmuxSession(id: req.id)
    return try HostdXPCCodec.successEmpty()
```

- [ ] **Step 3: Add `HostdProcessRegistry.interruptTmuxSession`**

In `HostdProcessRegistry.swift`:

```swift
public func interruptTmuxSession(id: UUID) async throws {
    let name = HostdTmuxSessionName.name(for: id)
    try await tmux.sendKeys(sessionName: name, keys: "C-c")
}
```

- [ ] **Step 4: Add transport entry**

In `HostdSocketTransport.swift`, alongside `terminateSession` (line ~57):

```swift
func interruptSession(_ request: Data) async throws -> Data {
    try await call(.interruptSession, payload: request)
}
```

Add `case interruptSession` to the wire enum used by `call`.

- [ ] **Step 5: Add `XPCHostdClient.interruptSession`**

In `XPCHostdClient.swift`, near `terminateSession(id:)` (line ~220):

```swift
func interruptSession(id: UUID) async throws {
    let request = try HostdXPCCodec.encode(HostdInterruptSessionRequest(id: id))
    _ = try await transport.interruptSession(request)
}
```

- [ ] **Step 6: Build and run hostd suite**

```bash
swift build
swift test --filter RoostTests.Hostd
```

Expected: SUCCESS / PASS.

- [ ] **Step 7: Commit**

```bash
jj commit -m "feat(hostd-client): implement interruptSession over the daemon socket"
```

---

# Phase 5: App Orchestration

## Task 5.0: AppState test rig (foundation for Phase 5 tests)

**Files:**
- Create: `Tests/MuxyTests/Models/AppStateTestRig.swift`

`AppState` has many dependencies (hostd client, terminal view registry, activity log, project store). Phase 5 tests need a small rig that fakes them. Land this once so subsequent tasks can reuse it.

- [ ] **Step 1: Inspect existing AppState construction**

```bash
rg -n 'AppState\(' Muxy MuxyServer | head -20
rg -n 'class AppState|struct AppState' Muxy/Models/AppState.swift
```

Identify the smallest set of dependencies required by the existing initializer. List them in a comment in your scratch (which dependencies are protocol types, which are concrete).

- [ ] **Step 2: Write the rig**

Create `Tests/MuxyTests/Models/AppStateTestRig.swift`:

```swift
import Foundation
@testable import Roost
@testable import RoostHostdCore

@MainActor
final class AppStateTestRig {
    var terminateCalls: [UUID] = []
    var removeViewCalls: [UUID] = []
    var createCalls: [(paneID: UUID, sessionID: UUID, command: String, agentKind: AgentKind)] = []
    var dispatchCount: Int = 0
    var slowTerminateNanoseconds: UInt64 = 0

    let viewRegistry = TerminalViewRegistry()
    let activityLog = ActivityLogStore.inMemory()
    lazy var fakeClient: FakeHostdClient = FakeHostdClient(rig: self)

    func makeAppState() -> AppState {
        let app = AppState(
            roostHostdClient: fakeClient,
            terminalViewRegistry: viewRegistry,
            activityLogStore: activityLog
            // ...add other required dependencies; substitute production values where possible
        )
        return app
    }
}

@MainActor
final class FakeHostdClient: RoostHostdClient {
    weak var rig: AppStateTestRig?
    init(rig: AppStateTestRig) { self.rig = rig }

    func terminateSession(id: UUID) async throws {
        if let ns = rig?.slowTerminateNanoseconds, ns > 0 {
            try? await Task.sleep(nanoseconds: ns)
        }
        rig?.terminateCalls.append(id)
    }
    func interruptSession(id: UUID) async throws { /* no-op */ }
    func sendSessionSignal(id: UUID, signal: HostdSessionSignal) async throws { /* no-op */ }
    // ...stub the rest with no-ops or `unsupportedRuntimeControl`
}
```

If `AppState`'s initializer takes properties not shown above, fill them in with the simplest concrete values that compile.

- [ ] **Step 3: Provide convenience helpers on `AppState` for tests**

Inside `Muxy/Models/AppState.swift` (or a `+Test.swift` extension under `Tests/`), add:

```swift
#if DEBUG
extension AppState {
    func makeAgentPane(kind: AgentKind) -> TerminalPaneState {
        // construct a TerminalPaneState fixture and insert it via the existing pane-registration path
        // returns the inserted pane for assertions
    }

    func testSetCapturedResume(_ paneID: UUID, captured: String) {
        dispatch(.markPaneSessionExited(paneID: paneID, capturedResumeCommand: captured))
    }
}
#endif
```

Match the existing test-helper conventions (`#if DEBUG` guard, `Test` suffix, etc.) used elsewhere in `Muxy/Models`.

- [ ] **Step 4: Build**

```bash
swift build
```

Expected: SUCCESS (rig compiles even though no tests exercise it yet).

- [ ] **Step 5: Commit**

```bash
jj commit -m "test(app): add AppStateTestRig for Phase 5 reload tests"
```

## Task 5.1: Compile + cache resume regex on preset

**Files:**
- Modify: `MuxyShared/Agent/AgentPreset.swift`
- Create: `Tests/MuxyTests/Agent/AgentPresetRegexCacheTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import MuxyShared
import Testing

@Suite("AgentPreset compiled regex")
struct AgentPresetRegexCacheTests {
    @Test
    func validRegexCompilesAndCaches() {
        let preset = AgentPreset(
            kind: .claudeCode,
            defaultCommand: "claude",
            resumeCommandRegex: #"(?m)^claude.*$"#
        )
        #expect(preset.compiledResumeRegex() != nil)
    }

    @Test
    func nilOverrideFallsBackToDefault() {
        let preset = AgentPreset(kind: .claudeCode, defaultCommand: "claude")
        // The resolved regex must come from AgentKind.claudeCode.defaultResumeRegex
        let resolved = preset.compiledResumeRegex()
        #expect(resolved != nil)
    }

    @Test
    func invalidRegexLogsAndReturnsNil() {
        let preset = AgentPreset(
            kind: .claudeCode,
            defaultCommand: "claude",
            resumeCommandRegex: "(unclosed"
        )
        // Implementation should log an error and return nil instead of throwing.
        #expect(preset.compiledResumeRegex() == nil)
    }
}
```

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.AgentPresetRegexCacheTests
```

Expected: build error.

- [ ] **Step 3: Add the helper**

In `AgentPreset.swift`, add a small actor-free cache (since `AgentPreset` is a value type, we cache through a static lookup keyed by the regex string):

```swift
import os

public extension AgentPreset {
    private static let regexCache = NSCache<NSString, NSRegularExpression>()
    private static let logger = Logger(subsystem: "Roost", category: "AgentPreset")

    func compiledResumeRegex() -> NSRegularExpression? {
        let pattern = resumeCommandRegex ?? kind.defaultResumeRegex
        guard let pattern else { return nil }
        let key = pattern as NSString
        if let cached = Self.regexCache.object(forKey: key) {
            return cached
        }
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            Self.regexCache.setObject(regex, forKey: key)
            return regex
        } catch {
            Self.logger.error("Invalid resumeCommandRegex \(pattern, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.AgentPresetRegexCacheTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(agent): cache compiled resumeCommandRegex per preset"
```

## Task 5.2: `AppState.handleSessionExit` extracts captured resume

**Files:**
- Modify: `Muxy/Models/AppState.swift`
- Create: `Tests/MuxyTests/Models/AppStateHandleSessionExitTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test
func handleSessionExitCapturesResume() {
    let app = AppState(/* test rig */)
    let pane = app.makeAgentPane(kind: .claudeCode)
    app.handleSessionExit(
        paneID: pane.id,
        sessionID: pane.sessionID,
        lastTail: "session continuing\nclaude --resume abc-123\n"
    )
    #expect(app.pane(pane.id)?.capturedResumeCommand == "claude --resume abc-123")
}

@Test
func handleSessionExitWithoutMatchClearsCaptured() {
    let app = AppState(/* test rig */)
    let pane = app.makeAgentPane(kind: .claudeCode)
    app.handleSessionExit(
        paneID: pane.id,
        sessionID: pane.sessionID,
        lastTail: "boring output"
    )
    #expect(app.pane(pane.id)?.capturedResumeCommand == nil)
}
```

(Use the test seam your project already provides for `AppState`. If none exists, write a minimal `AppState(testRig:)` initializer that injects deterministic dependencies.)

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.AppStateHandleSessionExitTests
```

Expected: failure.

- [ ] **Step 3: Implement**

Open `Muxy/Models/AppState.swift`. Add:

```swift
func handleSessionExit(paneID: UUID, sessionID: UUID, lastTail: String?) {
    guard let pane = pane(paneID) else { return }
    guard pane.sessionID == sessionID else { return }
    let preset = preset(for: pane.agentKind)
    let captured = extractResumeCommand(preset: preset, lastTail: lastTail)
    dispatch(.markPaneSessionExited(
        paneID: paneID,
        capturedResumeCommand: captured
    ))
    activityLogStore.append(.agentExited(paneID: paneID, captured: captured != nil))
}

private func extractResumeCommand(preset: AgentPreset, lastTail: String?) -> String? {
    guard let lastTail, let regex = preset.compiledResumeRegex() else { return nil }
    let range = NSRange(lastTail.startIndex..., in: lastTail)
    guard let match = regex.firstMatch(in: lastTail, range: range),
          let r = Range(match.range, in: lastTail)
    else { return nil }
    return String(lastTail[r]).trimmingCharacters(in: .whitespacesAndNewlines)
}
```

`.markPaneSessionExited` is added to `WorkspaceAction` in Task 5.3 — for now make sure the call compiles by stubbing the action there or land Task 5.3 first.

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.AppStateHandleSessionExitTests
```

Expected: PASS once Task 5.3 is also landed (these two should be one commit if you prefer).

- [ ] **Step 5: Commit (after Task 5.3 lands so it builds)**

Skip a separate commit here; combine with Task 5.3.

## Task 5.3: Add `WorkspaceAction` cases and reducer transitions

**Files:**
- Modify: `Muxy/Models/AppState.swift` (Action enum)
- Modify: `Muxy/Models/WorkspaceReducer.swift`
- Modify: `Tests/MuxyTests/Models/WorkspaceReducerTests.swift`

- [ ] **Step 1: Write reducer tests for the new actions**

```swift
@Test
func markPaneSessionExitedClearsToExited() {
    var state = WorkspaceState(/* with one running agent pane */)
    let id = state.firstPaneID()
    let effects = WorkspaceReducer.reduce(
        action: .markPaneSessionExited(paneID: id, capturedResumeCommand: "claude --resume abc"),
        state: &state
    )
    #expect(state.pane(id)?.lastState == .exited)
    #expect(state.pane(id)?.capturedResumeCommand == "claude --resume abc")
    _ = effects
}

@Test
func reloadAgentRefreshesSessionAndClearsBanners() {
    let originalCwd = URL(fileURLWithPath: "/Volumes/Roost/projectA")
    let newCwd = URL(fileURLWithPath: "/Volumes/Roost/projectA")
    var state = WorkspaceState(
        agentPane: TerminalPaneState.fixture(
            agentKind: .claudeCode,
            cwd: originalCwd,
            capturedResumeCommand: "claude --resume abc",
            binaryUpdateDetected: true,
            exitBannerDismissed: true,
            mtimeBannerDismissed: true,
            lastState: .exited
        )
    )
    let id = state.firstPaneID()
    let oldSession = state.pane(id)!.sessionID
    let oldKind = state.pane(id)!.agentKind
    let oldStartup = state.pane(id)!.startupCommand
    let newPath = URL(fileURLWithPath: "/usr/local/bin/claude")
    let newMtime = Date()
    let effects = WorkspaceReducer.reduce(
        action: .reloadAgent(
            paneID: id,
            mode: .resume,
            newSessionID: UUID(),
            command: "claude --x --resume abc",
            env: ["PATH": "/usr/bin"],
            cwd: newCwd,
            agentBinaryPath: newPath,
            agentBinaryMTime: newMtime
        ),
        state: &state
    )
    let pane = state.pane(id)!
    #expect(pane.sessionID != oldSession)
    #expect(pane.capturedResumeCommand == nil)
    #expect(pane.binaryUpdateDetected == false)
    #expect(pane.exitBannerDismissed == false)
    #expect(pane.mtimeBannerDismissed == false)
    #expect(pane.lastState == .preparing)
    #expect(pane.cwd == newCwd)
    #expect(pane.agentKind == oldKind)
    #expect(pane.startupCommand != oldStartup)
    #expect(pane.startupCommand == "claude --x --resume abc")
    #expect(pane.agentBinaryPath == newPath)
    #expect(pane.agentBinaryMTime == newMtime)
    _ = effects
}

@Test
func setBinaryUpdateDetectedTogglesFlag() {
    var state = WorkspaceState(/* one running pane */)
    let id = state.firstPaneID()
    _ = WorkspaceReducer.reduce(
        action: .setBinaryUpdateDetected(paneID: id, value: true),
        state: &state
    )
    #expect(state.pane(id)?.binaryUpdateDetected == true)
}

@Test
func dismissExitBannerSetsFlag() {
    var state = WorkspaceState(/* one exited pane */)
    let id = state.firstPaneID()
    _ = WorkspaceReducer.reduce(
        action: .dismissExitBanner(paneID: id),
        state: &state
    )
    #expect(state.pane(id)?.exitBannerDismissed == true)
}
```

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.WorkspaceReducerTests
```

Expected: build error (cases not defined).

- [ ] **Step 3: Add the action cases**

In `Muxy/Models/AppState.swift` (where `enum Action` is defined), add:

```swift
case markPaneSessionExited(paneID: UUID, capturedResumeCommand: String?)
case reloadAgent(
    paneID: UUID,
    mode: AgentReloadMode,
    newSessionID: UUID,
    command: String,
    env: [String: String],
    cwd: URL,
    agentBinaryPath: URL?,
    agentBinaryMTime: Date?
)
case setBinaryUpdateDetected(paneID: UUID, value: Bool)
case dismissExitBanner(paneID: UUID)
case dismissBinaryUpdateBanner(paneID: UUID)
```

- [ ] **Step 4: Handle them in `WorkspaceReducer.reduce`**

In `Muxy/Models/WorkspaceReducer.swift`, add cases in the switch:

```swift
case let .markPaneSessionExited(paneID, captured):
    if var pane = state.pane(paneID) {
        pane.capturedResumeCommand = captured
        pane.lastState = .exited
        state.replace(pane)
    }
    return WorkspaceSideEffects()

case let .reloadAgent(paneID, _, newSessionID, command, env, cwd, agentBinaryPath, agentBinaryMTime):
    if var pane = state.pane(paneID) {
        pane.sessionID = newSessionID
        pane.startupCommand = command
        pane.env = env
        pane.cwd = cwd
        pane.capturedResumeCommand = nil
        pane.binaryUpdateDetected = false
        pane.exitBannerDismissed = false
        pane.mtimeBannerDismissed = false
        pane.agentBinaryPath = agentBinaryPath
        pane.agentBinaryMTime = agentBinaryMTime
        pane.lastState = .preparing
        state.replace(pane)
    }
    return WorkspaceSideEffects()

case let .setBinaryUpdateDetected(paneID, value):
    if var pane = state.pane(paneID) {
        pane.binaryUpdateDetected = value
        state.replace(pane)
    }
    return WorkspaceSideEffects()

case let .dismissExitBanner(paneID):
    if var pane = state.pane(paneID) {
        pane.exitBannerDismissed = true
        state.replace(pane)
    }
    return WorkspaceSideEffects()

case let .dismissBinaryUpdateBanner(paneID):
    if var pane = state.pane(paneID) {
        pane.mtimeBannerDismissed = true
        state.replace(pane)
    }
    return WorkspaceSideEffects()
```

The `state.pane(...)` / `state.replace(pane)` helpers should match how the existing reducer fetches and writes back pane state — adapt to whatever idiom the rest of the file uses.

- [ ] **Step 5: Run tests**

```bash
swift test --filter RoostTests.WorkspaceReducerTests RoostTests.AppStateHandleSessionExitTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(workspace): add reload-related actions and reducer transitions"
```

## Task 5.4: `AppState.refreshBinaryUpdateBanner`

**Files:**
- Modify: `Muxy/Models/AppState.swift`
- Modify: `Tests/MuxyTests/Models/AppStateBinaryUpdateBannerTests.swift` (create)

- [ ] **Step 1: Write the failing test**

```swift
@Suite("AppState.refreshBinaryUpdateBanner")
struct AppStateBinaryUpdateBannerTests {
    @Test
    func detectsMtimeIncrease() throws {
        let app = AppState(/* test rig */)
        let pane = app.makeAgentPane(kind: .claudeCode)
        let bin = try createTempExecutable()
        app.setPaneBinary(pane.id, path: bin, mtime: Date(timeIntervalSinceNow: -60))
        try touchFile(bin)   // bumps mtime to now
        app.refreshBinaryUpdateBanner(paneID: pane.id)
        #expect(app.pane(pane.id)?.binaryUpdateDetected == true)
    }

    @Test
    func noChangeDoesNotDispatch() {
        let app = AppState(/* test rig */)
        let pane = app.makeAgentPane(kind: .claudeCode)
        let bin = try! createTempExecutable()
        let mtime = Date()
        app.setPaneBinary(pane.id, path: bin, mtime: mtime)
        let dispatchedBefore = app.testDispatchCount()
        app.refreshBinaryUpdateBanner(paneID: pane.id)
        #expect(app.testDispatchCount() == dispatchedBefore)
    }
}
```

(`createTempExecutable` and `touchFile` are small helpers; mirror style of existing tests.)

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.AppStateBinaryUpdateBannerTests
```

Expected: failure.

- [ ] **Step 3: Implement**

```swift
func refreshBinaryUpdateBanner(paneID: UUID) {
    guard let pane = pane(paneID),
          let path = pane.agentBinaryPath,
          let baseline = pane.agentBinaryMTime
    else { return }
    let attrs = try? FileManager.default.attributesOfItem(atPath: path.path)
    let now = (attrs?[.modificationDate] as? Date) ?? baseline
    let updated = now > baseline
    if updated != pane.binaryUpdateDetected {
        dispatch(.setBinaryUpdateDetected(paneID: paneID, value: updated))
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.AppStateBinaryUpdateBannerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(app): add refreshBinaryUpdateBanner driven by pane focus"
```

## Task 5.5: `AgentReloadCoordinator` (SIGINT tiered timeout)

**Files:**
- Create: `Muxy/Services/AgentReload/AgentReloadCoordinator.swift`
- Create: `Tests/MuxyTests/Services/AgentReloadCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
@testable import Roost
import Testing

@Suite("AgentReloadCoordinator")
struct AgentReloadCoordinatorTests {
    final class FakeClient: @unchecked Sendable {
        var interruptCalls = 0
        var killCalls = 0
        let exitAfterInterrupts: Int
        var exitedSignal = AsyncStream<Void>.makeStream()

        init(exitAfterInterrupts: Int) {
            self.exitAfterInterrupts = exitAfterInterrupts
        }

        func interrupt() async {
            interruptCalls += 1
            if interruptCalls >= exitAfterInterrupts {
                exitedSignal.continuation.yield()
                exitedSignal.continuation.finish()
            }
        }

        func kill() async {
            killCalls += 1
            exitedSignal.continuation.yield()
            exitedSignal.continuation.finish()
        }
    }

    @Test
    func exitsAfterFirstInterrupt() async {
        let fake = FakeClient(exitAfterInterrupts: 1)
        let coordinator = AgentReloadCoordinator(
            interruptStep: 50_000_000,
            forceKillStep: 50_000_000
        )
        await coordinator.driveExit(
            interrupt: { await fake.interrupt() },
            forceKill: { await fake.kill() },
            exitedStream: fake.exitedSignal.stream
        )
        #expect(fake.interruptCalls == 1)
        #expect(fake.killCalls == 0)
    }

    @Test
    func sendsSecondInterruptThenForceKills() async {
        let fake = FakeClient(exitAfterInterrupts: 99)   // never exits
        let coordinator = AgentReloadCoordinator(
            interruptStep: 50_000_000,
            forceKillStep: 50_000_000
        )
        await coordinator.driveExit(
            interrupt: { await fake.interrupt() },
            forceKill: { await fake.kill() },
            exitedStream: fake.exitedSignal.stream
        )
        #expect(fake.interruptCalls == 2)
        #expect(fake.killCalls == 1)
    }
}
```

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.AgentReloadCoordinatorTests
```

Expected: build error.

- [ ] **Step 3: Implement**

Create `Muxy/Services/AgentReload/AgentReloadCoordinator.swift`:

```swift
import Foundation

public actor AgentReloadCoordinator {
    public static let defaultInterruptStep: UInt64 = 3_000_000_000
    public static let defaultForceKillStep: UInt64 = 3_000_000_000

    private let interruptStep: UInt64
    private let forceKillStep: UInt64

    public init(
        interruptStep: UInt64 = AgentReloadCoordinator.defaultInterruptStep,
        forceKillStep: UInt64 = AgentReloadCoordinator.defaultForceKillStep
    ) {
        self.interruptStep = interruptStep
        self.forceKillStep = forceKillStep
    }

    public func driveExit(
        interrupt: @Sendable () async -> Void,
        forceKill: @Sendable () async -> Void,
        exitedStream: AsyncStream<Void>
    ) async {
        await interrupt()
        if await waitFor(stream: exitedStream, nanoseconds: interruptStep) { return }
        await interrupt()
        if await waitFor(stream: exitedStream, nanoseconds: forceKillStep) { return }
        await forceKill()
        _ = await waitFor(stream: exitedStream, nanoseconds: forceKillStep)
    }

    private func waitFor(stream: AsyncStream<Void>, nanoseconds: UInt64) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in stream { return true }
                return true
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: nanoseconds)
                return false
            }
            for await result in group {
                group.cancelAll()
                return result
            }
            return false
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.AgentReloadCoordinatorTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(agent): add AgentReloadCoordinator for SIGINT tiered exit"
```

## Task 5.6: `AppState.reloadAgent` orchestrator

**Files:**
- Modify: `Muxy/Models/AppState.swift`
- Create: `Tests/MuxyTests/Models/AppStateReloadAgentTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Suite("AppState.reloadAgent")
struct AppStateReloadAgentTests {
    @Test
    func freshReloadCallsTerminateThenCreate() async throws {
        let rig = TestRig()
        let app = AppState(rig: rig)
        let pane = app.makeAgentPane(kind: .claudeCode)
        await app.reloadAgent(paneID: pane.id, mode: .fresh)
        #expect(rig.terminateCalls == 1)
        #expect(rig.removeViewCalls.contains(pane.id))
        #expect(rig.createCalls.last?.command == "claude --dangerously-skip-permissions")
    }

    @Test
    func resumeReloadAppendsResumeArgs() async throws {
        let rig = TestRig()
        let app = AppState(rig: rig)
        let pane = app.makeAgentPane(kind: .claudeCode)
        app.testSetCapturedResume(pane.id, captured: "claude --resume abc-123")
        await app.reloadAgent(paneID: pane.id, mode: .resume)
        let last = rig.createCalls.last!
        #expect(last.command.contains("--resume abc-123"))
    }

    @Test
    func concurrentReloadIsDropped() async throws {
        let rig = TestRig(slowTerminate: true)
        let app = AppState(rig: rig)
        let pane = app.makeAgentPane(kind: .claudeCode)
        async let first: () = app.reloadAgent(paneID: pane.id, mode: .fresh)
        async let second: () = app.reloadAgent(paneID: pane.id, mode: .fresh)
        _ = await (first, second)
        #expect(rig.terminateCalls == 1)
    }
}
```

(`TestRig` is a small in-test type that records `terminateCalls`, `removeViewCalls`, `createCalls` and stands in for the daemon client + view registry.)

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.AppStateReloadAgentTests
```

Expected: failure.

- [ ] **Step 3: Implement**

In `AppState.swift`, add an `inFlightReloadPaneIDs: Set<UUID>` property (gated by an actor / main-actor lock that the rest of `AppState` already uses) and the orchestrator:

```swift
@MainActor
func reloadAgent(paneID: UUID, mode: AgentReloadMode) async {
    guard !inFlightReloadPaneIDs.contains(paneID) else { return }
    inFlightReloadPaneIDs.insert(paneID)
    defer { inFlightReloadPaneIDs.remove(paneID) }

    guard let pane = pane(paneID) else { return }
    let preset = preset(for: pane.agentKind)

    if mode == .resume, pane.lastState == .running {
        await runReloadInterrupt(paneID: paneID, oldSessionID: pane.sessionID)
    }

    guard let livePane = self.pane(paneID) else { return }
    let captured = livePane.capturedResumeCommand
    let oldSessionID = livePane.sessionID
    let newSessionID = UUID()
    let command = AgentReloadCommandBuilder.build(
        preset: preset,
        captured: captured,
        mode: mode
    )
    let env = TerminalPaneEnvironment.build(
        paneID: paneID,
        worktreeKey: livePane.worktreeKey,
        configured: preset.env
    )
    let cwd = livePane.cwd
    let binaryPath = AgentBinary.resolvePath(command: command, env: env)
    let mtime = binaryPath.flatMap { url -> Date? in
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.modificationDate] as? Date
    }

    do {
        try await roostHostdClient?.terminateSession(id: oldSessionID)
    } catch {
        Self.logger.warning("terminateSession(\(oldSessionID, privacy: .public)) failed during reload: \(error.localizedDescription, privacy: .public)")
    }
    terminalViewRegistry.removeView(for: paneID)

    dispatch(.reloadAgent(
        paneID: paneID,
        mode: mode,
        newSessionID: newSessionID,
        command: command,
        env: env,
        cwd: cwd,
        agentBinaryPath: binaryPath,
        agentBinaryMTime: mtime
    ))

    await createAgentSession(
        paneID: paneID,
        sessionID: newSessionID,
        command: command,
        env: env,
        cwd: cwd,
        agentKind: livePane.agentKind
    )

    activityLogStore.append(.agentReloaded(paneID: paneID, mode: mode))
}

private func runReloadInterrupt(paneID: UUID, oldSessionID: UUID) async {
    let coordinator = AgentReloadCoordinator()
    let exitedStream = sessionExitStream(for: oldSessionID)
    await coordinator.driveExit(
        interrupt: { [weak self] in
            do {
                try await self?.roostHostdClient?.interruptSession(id: oldSessionID)
            } catch {
                Self.logger.warning("interruptSession failed: \(error.localizedDescription, privacy: .public)")
            }
        },
        forceKill: { [weak self] in
            do {
                try await self?.roostHostdClient?.terminateSession(id: oldSessionID)
            } catch {
                Self.logger.warning("force terminateSession failed: \(error.localizedDescription, privacy: .public)")
            }
        },
        exitedStream: exitedStream
    )
}
```

`createAgentSession` is whatever path `AppState` already uses to spin up the first agent pane; the new method reuses it.

Add the `sessionExitStream(for:)` helper next to where `handleSessionExit` is invoked. Implementation:

```swift
@MainActor
private var pendingExitContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

@MainActor
func sessionExitStream(for sessionID: UUID) -> AsyncStream<Void> {
    AsyncStream { continuation in
        pendingExitContinuations[sessionID] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.pendingExitContinuations.removeValue(forKey: sessionID)
            }
        }
    }
}
```

In the existing exit handler (the place that calls `handleSessionExit`), after dispatching the state transition, fire the stream:

```swift
if let continuation = pendingExitContinuations.removeValue(forKey: sessionID) {
    continuation.yield(())
    continuation.finish()
}
```

Add `private static let logger = Logger(subsystem: "Roost", category: "AppState.reloadAgent")` near the top of the `AppState` extension that owns `reloadAgent`.

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.AppStateReloadAgentTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(app): add AppState.reloadAgent orchestrator with SIGINT escalation"
```

## Task 5.7: ActivityLogStore variants

**Files:**
- Modify: `MuxyShared/Agent/AgentActivityEvent.swift`
- Modify: `Muxy/Services/ActivityLogStore.swift`
- Modify: `Tests/MuxyTests/Services/ActivityLogStoreTests.swift`

- [ ] **Step 1: Add the new event variants**

In `AgentActivityEvent.swift`:

```swift
public enum AgentActivityEvent: Codable, Sendable, Hashable {
    // existing cases...
    case agentExited(paneID: UUID, captured: Bool)
    case agentReloaded(paneID: UUID, mode: AgentReloadMode)
}
```

(Make sure `AgentReloadMode` is `Codable` — it is, from Phase 2.)

- [ ] **Step 2: Update `ActivityLogStore` if it routes by case**

If `ActivityLogStore.append` switches on the event kind for any per-case behavior, add the new cases. Otherwise the generic append already handles them.

- [ ] **Step 3: Add tests**

In `ActivityLogStoreTests.swift`:

```swift
@Test
func appendsAgentExitedEvent() throws {
    let store = ActivityLogStore(/* in-memory rig */)
    let id = UUID()
    store.append(.agentExited(paneID: id, captured: true))
    #expect(store.events.last == .agentExited(paneID: id, captured: true))
}

@Test
func appendsAgentReloadedEvent() throws {
    let store = ActivityLogStore(/* in-memory rig */)
    let id = UUID()
    store.append(.agentReloaded(paneID: id, mode: .resume))
    #expect(store.events.last == .agentReloaded(paneID: id, mode: .resume))
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.ActivityLogStore
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(activity): record agentExited and agentReloaded events"
```

---

# Phase 6: UI

## Task 6.1: Context menu items

**Files:**
- Modify: `Muxy/Views/Workspace/TerminalPaneContextMenu.swift`
- Modify: existing snapshot tests for the context menu (search for `TerminalPaneContextMenu`)

- [ ] **Step 1: Add the menu items**

Open `TerminalPaneContextMenu.swift`. Inside the existing menu builder, gated by `pane.agentKind != .terminal && pane.hostdRuntimeOwnership == .hostdOwnedProcess`, add:

```swift
Divider()
Button("Reload Agent (Resume)") {
    Task { await appState.reloadAgent(paneID: pane.id, mode: .resume) }
}
.disabled(pane.lastState == .running && pane.capturedResumeCommand == nil
       || pane.agentKind.resumeStrategy == .notSupported)

Button("Reload Agent (Fresh)") {
    Task { await appState.reloadAgent(paneID: pane.id, mode: .fresh) }
}
```

- [ ] **Step 2: Build**

```bash
swift build
```

Expected: SUCCESS.

- [ ] **Step 3: Update / add a snapshot test that lists menu items for an agent pane**

If your project has a context-menu snapshot test, add an assertion that both items appear for a `.claudeCode` pane and neither appears for a `.terminal` pane.

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.TerminalPaneContextMenuTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(ui): add Reload Agent menu items to pane context menu"
```

## Task 6.2: `AgentReloadBanner` view

**Files:**
- Create: `Muxy/Views/Terminal/AgentReloadBanner.swift`
- Create: `Tests/MuxyTests/Views/AgentReloadBannerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import SwiftUI
import Testing
@testable import Roost

@Suite("AgentReloadBanner")
struct AgentReloadBannerTests {
    @Test
    func exitVariantShowsResumeAndRestart() {
        let banner = AgentReloadBanner.Model.exit(
            agentName: "claude",
            captured: "claude --resume abc",
            onResume: {},
            onFresh: {},
            onDismiss: {}
        )
        #expect(banner.primaryButtonEnabled)
        #expect(banner.primaryLabel == "Resume")
        #expect(banner.secondaryLabel == "Restart fresh")
    }

    @Test
    func exitWithoutCaptureDisablesResume() {
        let banner = AgentReloadBanner.Model.exit(
            agentName: "claude",
            captured: nil,
            onResume: {},
            onFresh: {},
            onDismiss: {}
        )
        #expect(!banner.primaryButtonEnabled)
    }

    @Test
    func mtimeVariantShowsReload() {
        let banner = AgentReloadBanner.Model.binaryUpdate(
            agentName: "claude",
            onReload: {},
            onDismiss: {}
        )
        #expect(banner.primaryLabel == "Reload")
        #expect(banner.secondaryLabel == nil)
    }
}
```

- [ ] **Step 2: Run, see failure**

```bash
swift test --filter RoostTests.AgentReloadBannerTests
```

Expected: failure.

- [ ] **Step 3: Implement**

Create `Muxy/Views/Terminal/AgentReloadBanner.swift`:

```swift
import SwiftUI

struct AgentReloadBanner: View {
    let model: Model

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.iconName)
                .foregroundStyle(model.tint)
            Text(model.title)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            if let secondary = model.secondaryLabel {
                Button(secondary, action: model.onSecondary).buttonStyle(.bordered)
            }
            Button(model.primaryLabel, action: model.onPrimary)
                .buttonStyle(.borderedProminent)
                .disabled(!model.primaryButtonEnabled)
            Button(action: model.onDismiss) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(model.tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    struct Model {
        let title: String
        let iconName: String
        let tint: Color
        let primaryLabel: String
        let primaryButtonEnabled: Bool
        let onPrimary: () -> Void
        let secondaryLabel: String?
        let onSecondary: () -> Void
        let onDismiss: () -> Void

        static func exit(
            agentName: String,
            captured: String?,
            onResume: @escaping () -> Void,
            onFresh: @escaping () -> Void,
            onDismiss: @escaping () -> Void
        ) -> Model {
            Model(
                title: "\(agentName) exited.",
                iconName: "circle.fill",
                tint: .orange,
                primaryLabel: "Resume",
                primaryButtonEnabled: captured != nil,
                onPrimary: onResume,
                secondaryLabel: "Restart fresh",
                onSecondary: onFresh,
                onDismiss: onDismiss
            )
        }

        static func binaryUpdate(
            agentName: String,
            onReload: @escaping () -> Void,
            onDismiss: @escaping () -> Void
        ) -> Model {
            Model(
                title: "\(agentName) binary updated since launch.",
                iconName: "arrow.triangle.2.circlepath",
                tint: .blue,
                primaryLabel: "Reload",
                primaryButtonEnabled: true,
                onPrimary: onReload,
                secondaryLabel: nil,
                onSecondary: {},
                onDismiss: onDismiss
            )
        }
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter RoostTests.AgentReloadBannerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(ui): add AgentReloadBanner with exit and binary-update variants"
```

## Task 6.3: Wire the banner + focus refresh into `TerminalPane`

**Files:**
- Modify: `Muxy/Views/Terminal/TerminalPane.swift`

- [ ] **Step 1: Add the overlay**

Open `TerminalPane.swift`. Wrap the existing terminal body in an overlay:

```swift
ZStack {
    GhosttyTerminalRepresentable(/* existing args */)
        .id(pane.sessionID)
}
.overlay(alignment: .top) {
    bannerView
}
```

- [ ] **Step 2: Build the banner view**

```swift
@ViewBuilder
private var bannerView: some View {
    if pane.agentKind != .terminal,
       pane.hostdRuntimeOwnership == .hostdOwnedProcess {
        if pane.lastState == .exited && !pane.exitBannerDismissed {
            AgentReloadBanner(model: .exit(
                agentName: pane.agentKind.displayName,
                captured: pane.capturedResumeCommand,
                onResume: { Task { await appState.reloadAgent(paneID: pane.id, mode: .resume) } },
                onFresh: { Task { await appState.reloadAgent(paneID: pane.id, mode: .fresh) } },
                onDismiss: { appState.dispatch(.dismissExitBanner(paneID: pane.id)) }
            ))
            .padding(8)
        } else if pane.lastState == .running
               && pane.binaryUpdateDetected
               && !pane.mtimeBannerDismissed {
            AgentReloadBanner(model: .binaryUpdate(
                agentName: pane.agentKind.displayName,
                onReload: { Task { await appState.reloadAgent(paneID: pane.id, mode: .resume) } },
                onDismiss: { appState.dispatch(.dismissBinaryUpdateBanner(paneID: pane.id)) }
            ))
            .padding(8)
        }
    }
}
```

- [ ] **Step 3: Trigger `refreshBinaryUpdateBanner` on focus and scenePhase**

Add to the same view:

```swift
.onAppear { appState.refreshBinaryUpdateBanner(paneID: pane.id) }
.onChange(of: focusedPaneID) { _, new in
    if new == pane.id { appState.refreshBinaryUpdateBanner(paneID: pane.id) }
}
.onChange(of: scenePhase) { _, phase in
    if phase == .active && focusedPaneID == pane.id {
        appState.refreshBinaryUpdateBanner(paneID: pane.id)
    }
}
```

(Adapt environment value names — `focusedPaneID`, `scenePhase` — to whatever the project already defines. If `focusedPaneID` does not exist as an `@Environment`, route the trigger via `.onTapGesture` / `Window.focusedScene`.)

- [ ] **Step 4: Build and manually verify**

```bash
swift build
swift run Roost
```

Manually:
1. Launch a Claude pane.
2. Run `touch $(which claude)` in a separate terminal.
3. Click the pane to refocus → confirm the binary-update banner appears.
4. `/exit` Claude → confirm the exit banner appears with `Resume` enabled.
5. Click `Resume` → confirm the new session starts with `--resume`.

Note any issues.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(ui): wire AgentReloadBanner overlay and focus-driven refresh"
```

---

# Phase 7: Integration and Docs

## Task 7.1: End-to-end integration test

**Files:**
- Create: `Tests/MuxyTests/Integration/AgentReloadIntegrationTests.swift`

- [ ] **Step 1: Write the test**

```swift
import Foundation
@testable import Roost
@testable import RoostHostdCore
import Testing

@Suite("Agent reload integration", .enabled(if: tmuxAvailable()))
struct AgentReloadIntegrationTests {
    @Test
    func reloadResumeReusesPaneIDAndRotatesSessionID() async throws {
        let rig = AppStateTestRig()
        let app = await rig.makeAppState()
        let pane = await app.makeAgentPane(kind: .claudeCode)
        let oldSession = pane.sessionID

        try await injectFakeAgentExit(
            sessionID: oldSession,
            output: "claude --resume abc-int-123\n"
        )
        try await waitFor(timeout: 5) {
            await app.pane(pane.id)?.lastState == .exited
        }
        #expect(await app.pane(pane.id)?.capturedResumeCommand == "claude --resume abc-int-123")

        await app.reloadAgent(paneID: pane.id, mode: .resume)
        #expect(await app.pane(pane.id)?.id == pane.id)
        #expect(await app.pane(pane.id)?.sessionID != oldSession)
    }
}

func injectFakeAgentExit(sessionID: UUID, output: String) async throws {
    let controller = HostdTmuxController()
    let name = HostdTmuxSessionName.name(for: sessionID)
    let escaped = output.replacingOccurrences(of: "'", with: "'\\''")
    let command = "printf '%s' '\(escaped)' && exit 0"
    try await controller.launch(
        sessionName: name,
        workspacePath: "/tmp",
        command: command,
        environment: [:]
    )
}

func waitFor(timeout seconds: Double, _ predicate: @Sendable () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if await predicate() { return }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw NSError(domain: "AgentReloadIntegrationTests", code: -1, userInfo: [
        NSLocalizedDescriptionKey: "waitFor timed out"
    ])
}
```

`injectFakeAgentExit` reuses `HostdTmuxController.launch`, which already wires `remain-on-exit on` (Task 3.2) and is picked up by the running daemon's exit watcher (Task 3.4). The fake bash command echoes the resume hint and exits, mimicking what a real Claude / Codex binary would do on `/exit`. Adjust `workspacePath` and `environment` to match what `AppStateTestRig` configures the pane with so the watcher fires for the same session id.

- [ ] **Step 2: Run**

```bash
swift test --filter RoostTests.AgentReloadIntegrationTests
```

Expected: PASS (skipped if `tmux` is missing).

- [ ] **Step 3: Commit**

```bash
jj commit -m "test(agent): end-to-end reload integration with real tmux"
```

## Task 7.2: Update `docs/architecture.md`

**Files:**
- Modify: `docs/architecture.md`

- [ ] **Step 1: Add a short subsection under Hostd Live Attach**

Append (after the existing tmux paragraph):

```markdown
- **Agent Reload**: For tmux-backed agent panes, hostd sets `remain-on-exit on`
  on the Roost-owned session and watches `pane_dead` after the agent exits.
  When the agent dies, hostd captures the last 200 lines of the pane via
  `tmux capture-pane -p -S -200 -N -J`, persists the captured tail to
  `SessionStore.lastTail`, and reports it on the SessionExit IPC notice.
  The app extracts a resume command per-`AgentKind` (Claude appends
  `--resume <id>` to the preset; Codex uses the captured `codex resume <id>`
  verbatim). Reload tears down the ghostty surface and creates a new session
  inside the same `paneID`, with `GhosttyTerminalRepresentable.id(pane.sessionID)`
  driving SwiftUI to recreate the NSView. UI surfaces are an exit banner, a
  binary-update banner triggered on pane focus by mtime comparison, and pane
  context-menu items.
```

- [ ] **Step 2: Run all checks**

```bash
scripts/checks.sh
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
jj commit -m "docs: document agent reload and resume flow in architecture.md"
```

---

## Final Notes

- [ ] After landing all phases, push the bookmark for review:

```bash
jj tug
jj git push
```

- [ ] Manual smoke test on a fresh build:
  1. Launch `Roost`, open a Claude pane.
  2. `brew upgrade claude` (or `touch $(which claude)`) in a separate terminal.
  3. Refocus the pane — binary-update banner should appear.
  4. Click `Reload` — confirm Claude restarts and the resumed session loads.
  5. Type `/exit` inside Claude — exit banner should appear with `Resume` enabled if the captured command was matched.
  6. Click `Resume` — confirm the new pane resumes the previous conversation.
  7. Repeat for Codex (subcommand-based resume).
  8. Repeat for Gemini — `Resume` is disabled, only `Restart fresh` is offered.
- [ ] No new git commands; commits use `jj commit -m`.
- [ ] If a task fails partway through, fix the underlying issue before adding a new commit; do not amend pre-existing commits.
