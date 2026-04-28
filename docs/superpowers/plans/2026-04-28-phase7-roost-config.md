# Phase 7 — Roost Config + Custom Agent Presets

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Introduce `.roost/config.json` as the unified per-project config file. Phase 7 covers the schema, the loader, and the highest-value field — `agentPresets` (user-customizable overrides for the built-in `AgentPresetCatalog`). Setup commands migrate from `.muxy/worktree.json` to `.roost/config.json` while keeping backward compatibility.

**Architecture:** `RoostConfig` is a versioned, decode-tolerant DTO in `MuxyShared`. Loader path: `<project>/.roost/config.json` first; fall back to `<project>/.muxy/worktree.json` for the `setup` field only. `AgentPresetCatalog.preset(for:configuredPresets:)` accepts an override list — call sites that have a `RoostConfig` pass it in; existing call sites keep working unchanged.

**Tech Stack:** Swift 6, swift-testing, existing JSON schema-version tolerant pattern (mirrors Phase 2.1).

**Locked decisions:**
- Schema version `1`. Future fields land via `decodeIfPresent` + version bumps.
- File path: `<project>/.roost/config.json`. Legacy `.muxy/worktree.json` continues to work for the `setup` field; new fields require `.roost/config.json`.
- Empty / absent config = use built-in defaults everywhere.
- `agentPresets` is an additive override: any preset whose `kind` matches a built-in REPLACES the built-in for that kind. Unmentioned kinds keep their built-in defaults.
- `chmod 600` on first write — deferred (not write path in Phase 7; only read).
- `defaultWorkspaceLocation`, `teardown`, `env`, `notifications`, Keychain references — **schema reserves the keys but Phase 7 ignores them** (decoded but not consumed). Each gets its own future phase.

**Out of scope:**
- Writing `.roost/config.json` (only reading in Phase 7).
- `defaultWorkspaceLocation` integration (would change worktree creation paths).
- `teardown` execution.
- `env` resolution / Keychain.
- `notifications` config.
- Settings UI for editing config inline.

---

## File Structure

**Create:**
- `MuxyShared/Config/RoostConfig.swift` — DTO + sub-types
- `Muxy/Services/Config/RoostConfigLoader.swift` — loader (in MuxyShared if you prefer; we keep in `Muxy/Services` because it's not used by tests-only)
- `Tests/MuxyTests/Config/RoostConfigTests.swift` — schema decode tests
- `Tests/MuxyTests/Config/RoostConfigLoaderTests.swift` — loader tests

**Modify:**
- `MuxyShared/Agent/AgentPreset.swift` — add `AgentPresetCatalog.preset(for:configuredPresets:)` overload
- `Tests/MuxyTests/Agent/AgentPresetTests.swift` — extend tests for the override behavior

---

## Task 1: RoostConfig schema

**Files:**
- Create: `MuxyShared/Config/RoostConfig.swift`
- Test: `Tests/MuxyTests/Config/RoostConfigTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import MuxyShared
import Testing

@Suite("RoostConfig")
struct RoostConfigTests {
    @Test("decodes minimal v1 config")
    func minimalDecode() throws {
        let json = """
        { "schemaVersion": 1 }
        """
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.schemaVersion == 1)
        #expect(config.setup.isEmpty)
        #expect(config.agentPresets.isEmpty)
    }

    @Test("decodes setup commands as objects")
    func setupObjects() throws {
        let json = """
        {
          "schemaVersion": 1,
          "setup": [
            { "name": "install", "command": "pnpm install" },
            { "command": "pnpm dev" }
          ]
        }
        """
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.setup.count == 2)
        #expect(config.setup[0].name == "install")
        #expect(config.setup[1].command == "pnpm dev")
        #expect(config.setup[1].name == nil)
    }

    @Test("decodes agentPresets override")
    func agentPresetsOverride() throws {
        let json = """
        {
          "schemaVersion": 1,
          "agentPresets": [
            {
              "name": "Custom Claude",
              "kind": "claudeCode",
              "command": "claude --model sonnet",
              "cardinality": "dedicated"
            }
          ]
        }
        """
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.agentPresets.count == 1)
        let preset = config.agentPresets[0]
        #expect(preset.name == "Custom Claude")
        #expect(preset.kind == .claudeCode)
        #expect(preset.command == "claude --model sonnet")
        #expect(preset.cardinality == .dedicated)
    }

    @Test("missing schemaVersion → default 1")
    func missingSchemaVersion() throws {
        let json = "{}"
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.schemaVersion == 1)
    }

    @Test("unknown agentKind raw value rejects the entry but keeps the file")
    func unknownAgentKindIgnored() throws {
        let json = """
        {
          "schemaVersion": 1,
          "agentPresets": [
            { "name": "Future", "kind": "future-agent", "command": "future", "cardinality": "shared" },
            { "name": "Codex", "kind": "codex", "command": "codex", "cardinality": "shared" }
          ]
        }
        """
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.agentPresets.count == 1)
        #expect(config.agentPresets.first?.kind == .codex)
    }

    @Test("legacy fields don't break decode")
    func legacyFieldsTolerated() throws {
        let json = """
        {
          "schemaVersion": 1,
          "defaultWorkspaceLocation": "/tmp/wt",
          "teardown": [{ "command": "echo bye" }],
          "env": { "FOO": "bar" },
          "notifications": { "enabled": true }
        }
        """
        let config = try JSONDecoder().decode(RoostConfig.self, from: Data(json.utf8))
        #expect(config.schemaVersion == 1)
        #expect(config.setup.isEmpty)
    }
}
```

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter RoostConfigTests
```

- [ ] **Step 3: Implement**

Create `MuxyShared/Config/RoostConfig.swift`:

```swift
import Foundation

public struct RoostConfig: Sendable, Codable {
    public let schemaVersion: Int
    public let setup: [RoostConfigSetupCommand]
    public let agentPresets: [RoostConfigAgentPreset]

    public init(
        schemaVersion: Int = 1,
        setup: [RoostConfigSetupCommand] = [],
        agentPresets: [RoostConfigAgentPreset] = []
    ) {
        self.schemaVersion = schemaVersion
        self.setup = setup
        self.agentPresets = agentPresets
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case setup
        case agentPresets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        setup = (try? container.decodeIfPresent([RoostConfigSetupCommand].self, forKey: .setup)) ?? []

        if let raw = try? container.decodeIfPresent([RoostConfigAgentPreset].self, forKey: .agentPresets) {
            agentPresets = raw
        } else {
            let rawArray = (try? container.decodeIfPresent([RoostConfigAgentPresetTolerant].self, forKey: .agentPresets)) ?? []
            agentPresets = rawArray.compactMap { $0.preset }
        }
    }
}

public struct RoostConfigSetupCommand: Sendable, Codable, Hashable {
    public let command: String
    public let name: String?

    public init(command: String, name: String? = nil) {
        self.command = command
        self.name = name
    }
}

public enum RoostConfigCardinality: String, Sendable, Codable {
    case shared
    case dedicated
}

public struct RoostConfigAgentPreset: Sendable, Codable, Hashable {
    public let name: String
    public let kind: AgentKind
    public let command: String?
    public let cardinality: RoostConfigCardinality

    public init(
        name: String,
        kind: AgentKind,
        command: String?,
        cardinality: RoostConfigCardinality = .shared
    ) {
        self.name = name
        self.kind = kind
        self.command = command
        self.cardinality = cardinality
    }
}

private struct RoostConfigAgentPresetTolerant: Decodable {
    let preset: RoostConfigAgentPreset?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RoostConfigAgentPreset.CodingKeys.self)
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        guard let kindRaw = try container.decodeIfPresent(String.self, forKey: .kind),
              let kind = AgentKind(rawValue: kindRaw)
        else {
            preset = nil
            return
        }
        let command = try container.decodeIfPresent(String.self, forKey: .command)
        let cardinality = (try? container.decodeIfPresent(RoostConfigCardinality.self, forKey: .cardinality)) ?? .shared
        preset = RoostConfigAgentPreset(name: name, kind: kind, command: command, cardinality: cardinality)
    }
}

extension RoostConfigAgentPreset {
    fileprivate enum CodingKeys: String, CodingKey {
        case name, kind, command, cardinality
    }
}
```

The `RoostConfigAgentPresetTolerant` indirection gracefully drops entries with unknown `kind` values rather than failing the whole config decode.

- [ ] **Step 4: Run targeted + full**

```bash
swift test --filter RoostConfigTests
swift test 2>&1 | tail -3
```

Expected: 6 new tests pass; total all green.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(config): RoostConfig schema (v1) + tolerant decode"
```

---

## Task 2: RoostConfigLoader

**Files:**
- Create: `Muxy/Services/Config/RoostConfigLoader.swift`
- Test: `Tests/MuxyTests/Config/RoostConfigLoaderTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("RoostConfigLoader")
struct RoostConfigLoaderTests {
    private func makeTempProject() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("returns nil when no config files exist")
    func missingConfig() {
        let project = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let config = RoostConfigLoader.load(fromProjectPath: project.path)
        #expect(config == nil)
    }

    @Test("loads .roost/config.json when present")
    func loadsRoostConfig() throws {
        let project = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let dir = project.appendingPathComponent(".roost")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        { "schemaVersion": 1, "setup": [{ "command": "make" }] }
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("config.json"))
        let config = RoostConfigLoader.load(fromProjectPath: project.path)
        #expect(config?.setup.first?.command == "make")
    }

    @Test("falls back to legacy .muxy/worktree.json setup commands")
    func legacyFallback() throws {
        let project = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let dir = project.appendingPathComponent(".muxy")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        { "setup": [{ "command": "pnpm install" }, { "command": "pnpm dev" }] }
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("worktree.json"))
        let config = RoostConfigLoader.load(fromProjectPath: project.path)
        #expect(config?.setup.count == 2)
        #expect(config?.setup.first?.command == "pnpm install")
        #expect(config?.agentPresets.isEmpty == true)
    }

    @Test(".roost/config.json wins over legacy when both present")
    func roostBeatsLegacy() throws {
        let project = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let roostDir = project.appendingPathComponent(".roost")
        try FileManager.default.createDirectory(at: roostDir, withIntermediateDirectories: true)
        try Data("""
            { "schemaVersion": 1, "setup": [{ "command": "make" }] }
            """.utf8
        ).write(to: roostDir.appendingPathComponent("config.json"))

        let muxyDir = project.appendingPathComponent(".muxy")
        try FileManager.default.createDirectory(at: muxyDir, withIntermediateDirectories: true)
        try Data("""
            { "setup": [{ "command": "legacy" }] }
            """.utf8
        ).write(to: muxyDir.appendingPathComponent("worktree.json"))

        let config = RoostConfigLoader.load(fromProjectPath: project.path)
        #expect(config?.setup.first?.command == "make")
    }
}
```

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter RoostConfigLoaderTests
```

- [ ] **Step 3: Implement**

Create `Muxy/Services/Config/RoostConfigLoader.swift`:

```swift
import Foundation
import MuxyShared

enum RoostConfigLoader {
    static func load(fromProjectPath projectPath: String) -> RoostConfig? {
        if let config = loadRoost(fromProjectPath: projectPath) {
            return config
        }
        return loadLegacy(fromProjectPath: projectPath)
    }

    private static func loadRoost(fromProjectPath projectPath: String) -> RoostConfig? {
        let url = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".roost")
            .appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RoostConfig.self, from: data)
    }

    private static func loadLegacy(fromProjectPath projectPath: String) -> RoostConfig? {
        let url = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".muxy")
            .appendingPathComponent("worktree.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let legacy = try? JSONDecoder().decode(LegacyWorktreeConfig.self, from: data) else { return nil }
        return RoostConfig(
            schemaVersion: 1,
            setup: legacy.setup.map { RoostConfigSetupCommand(command: $0.command, name: $0.name) },
            agentPresets: []
        )
    }
}

private struct LegacyWorktreeConfig: Decodable {
    struct Entry: Decodable {
        let command: String
        let name: String?
    }
    let setup: [Entry]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let entries = try? container.decode([Entry].self, forKey: .setup) {
            setup = entries
        } else if let strings = try? container.decode([String].self, forKey: .setup) {
            setup = strings.map { Entry(command: $0, name: nil) }
        } else {
            setup = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case setup
    }
}
```

The `LegacyWorktreeConfig` is a private mirror that handles both the object form `[{ command: ..., name: ... }]` and the historical string form `[..., ...]`.

- [ ] **Step 4: Run targeted + full**

```bash
swift test --filter RoostConfigLoaderTests
swift test 2>&1 | tail -3
```

Expected: 4 new tests pass; total all green.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(config): RoostConfigLoader (.roost wins, .muxy fallback for setup)"
```

---

## Task 3: AgentPresetCatalog override

**Files:**
- Modify: `MuxyShared/Agent/AgentPreset.swift`
- Modify: `Tests/MuxyTests/Agent/AgentPresetTests.swift`

- [ ] **Step 1: Append tests**

In `Tests/MuxyTests/Agent/AgentPresetTests.swift`, append two new tests inside the existing `@Suite("AgentPreset") struct AgentPresetTests`:

```swift
    @Test("configured override wins for a known kind")
    func overrideWinsForKind() {
        let configured = [RoostConfigAgentPreset(
            name: "Custom Claude",
            kind: .claudeCode,
            command: "claude --model opus",
            cardinality: .dedicated
        )]
        let preset = AgentPresetCatalog.preset(for: .claudeCode, configuredPresets: configured)
        #expect(preset.defaultCommand == "claude --model opus")
        #expect(preset.requiresDedicatedWorkspace == true)
    }

    @Test("kinds without override fall back to built-in")
    func unrelatedKindUsesBuiltIn() {
        let configured = [RoostConfigAgentPreset(
            name: "Custom Claude",
            kind: .claudeCode,
            command: "claude --model opus",
            cardinality: .dedicated
        )]
        let preset = AgentPresetCatalog.preset(for: .codex, configuredPresets: configured)
        #expect(preset.defaultCommand == "codex")
        #expect(preset.requiresDedicatedWorkspace == false)
    }
```

- [ ] **Step 2: Run, expect failure**

```bash
swift test --filter AgentPresetTests
```

- [ ] **Step 3: Implement override overload**

In `MuxyShared/Agent/AgentPreset.swift`, modify the existing `AgentPresetCatalog`. Replace its body with:

```swift
public enum AgentPresetCatalog {
    public static func preset(for kind: AgentKind) -> AgentPreset {
        builtIn(for: kind)
    }

    public static func preset(
        for kind: AgentKind,
        configuredPresets: [RoostConfigAgentPreset]
    ) -> AgentPreset {
        if let override = configuredPresets.first(where: { $0.kind == kind }) {
            return AgentPreset(
                kind: kind,
                defaultCommand: override.command,
                requiresDedicatedWorkspace: override.cardinality == .dedicated
            )
        }
        return builtIn(for: kind)
    }

    private static func builtIn(for kind: AgentKind) -> AgentPreset {
        switch kind {
        case .terminal:
            AgentPreset(kind: .terminal, defaultCommand: nil)
        case .claudeCode:
            AgentPreset(kind: .claudeCode, defaultCommand: "claude")
        case .codex:
            AgentPreset(kind: .codex, defaultCommand: "codex")
        case .geminiCli:
            AgentPreset(kind: .geminiCli, defaultCommand: "gemini")
        case .openCode:
            AgentPreset(kind: .openCode, defaultCommand: "opencode")
        }
    }
}
```

The existing `preset(for:)` (no override) call sites continue to work — they receive built-in defaults.

- [ ] **Step 4: Run targeted + full**

```bash
swift test --filter AgentPresetTests
swift test 2>&1 | tail -3
```

Expected: 6 tests pass (4 existing + 2 new); total all green.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(agent): AgentPresetCatalog accepts configured-preset overrides"
```

---

## Task 4: Wire RoostConfig into TabArea.createAgentTab

**Files:**
- Modify: `Muxy/Models/TabArea.swift`

When creating an agent tab, look up the project's `.roost/config.json` and apply preset overrides if present.

- [ ] **Step 1: Modify createAgentTab**

In `Muxy/Models/TabArea.swift`, find `createAgentTab(kind:)` (around line 67). Replace with:

```swift
    @discardableResult
    func createAgentTab(kind: AgentKind) -> TerminalTab {
        let configured = RoostConfigLoader.load(fromProjectPath: projectPath)?.agentPresets ?? []
        let preset = AgentPresetCatalog.preset(for: kind, configuredPresets: configured)
        let pane = TerminalPaneState(
            projectPath: projectPath,
            title: preset.kind.displayName,
            startupCommand: preset.defaultCommand,
            agentKind: kind
        )
        let tab = TerminalTab(pane: pane)
        insertTab(tab)
        return tab
    }
```

The `@discardableResult` keeps existing call sites unchanged. The lookup is best-effort — if config doesn't exist or fails to parse, we fall back to built-in.

- [ ] **Step 2: Build + test**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -3
```

Expected SUCCESS, all green (existing tests pass — `RoostConfigLoader` returns nil for test paths without config).

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(agent): TabArea.createAgentTab consults .roost/config.json for overrides"
```

---

## Task 5: Migration plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append after the existing Phase 7 section's prose**

Append in the Phase 7 section:

```markdown
**Status (2026-04-28): Phase 7 (config + presets) v1 landed.**

- `RoostConfig` (versioned, decode-tolerant) lives in `MuxyShared/Config/`. Schema version 1.
- `RoostConfigLoader.load(fromProjectPath:)` reads `.roost/config.json` first; falls back to legacy `.muxy/worktree.json` for the `setup` field only (back-compat).
- `AgentPresetCatalog.preset(for:configuredPresets:)` overload returns user overrides when a configured preset matches the requested `AgentKind`; otherwise built-in fallback. `cardinality: "dedicated"` maps to `requiresDedicatedWorkspace = true`.
- `TabArea.createAgentTab` now consults the loader at creation time — best-effort, falls back to built-ins on missing/invalid config.
- Out of scope this phase (deferred): `defaultWorkspaceLocation`, `teardown`, `env` resolution / Keychain references, `notifications` config, settings UI for editing config inline. Schema reserves these keys but does not consume them.
- Setup commands continue to run via `WorktreeSetupRunner` reading `.muxy/worktree.json` directly — migration of that path to `RoostConfig.setup` is a follow-up to keep this plan focused.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(plan): mark Phase 7 (config + presets) v1 landed"
```

---

## Self-Review Checklist

- [ ] No new SPM dependencies.
- [ ] Decode-tolerant: missing `schemaVersion` defaults to 1; unknown agentKind drops entry not the file.
- [ ] Backward compat: `.muxy/worktree.json` still works for setup.
- [ ] Existing built-in preset behavior unchanged when no `.roost/config.json` is present.
- [ ] No comments added.
- [ ] All builds + tests green.
