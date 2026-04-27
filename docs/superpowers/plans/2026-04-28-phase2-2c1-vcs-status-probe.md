# Phase 2.2c1 — VcsStatusProbe + resolver

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Route the two existing `hasUncommittedChanges` view callers (`ExpandedProjectRow.swift:341`, `WorktreePopover.swift:89`) through a `VcsStatusProbe` abstraction with kind-specific implementations. Mirror the resolver/environment pattern from Phase 2.2b2. `isGitRepository` callers and `VCSTabState.deleteBranch` deferred — different scopes.

**Architecture:** `VcsStatusProbe` is a `Sendable` protocol exposing `hasUncommittedChanges(at:)`. `GitStatusProbe` wraps `GitWorktreeService.shared.hasUncommittedChanges`. `JjStatusProbe` runs `jj status --ignore-working-copy --color=never` via `JjProcessRunner`, parses with `JjStatusParser`, returns `!entries.isEmpty || hasConflicts`. `VcsStatusProbeFactory.probe(for: VcsKind)` selects. `VcsStatusProbeResolver` wraps in an injectable closure with a SwiftUI environment key. View callers read the resolver via `@Environment(\.vcsStatusProbeResolver)`, get the probe matching `worktree.vcsKind`, and call `hasUncommittedChanges`.

**Tech Stack:** Swift 6, swift-testing, SwiftUI environment.

**Out of scope (separate plans):**
- `isGitRepository` callers (`ExpandedProjectRow:59`, `ProjectRow:61`) — gating UI behavior; needs a different "is repo at all" probe semantic.
- `VCSTabState.deleteBranch` — large class refactor.
- Sidebar visual jj badges, `WorktreeDTO` IPC.

---

## File Structure

New:
```
Muxy/Services/Vcs/VcsStatusProbe.swift              - protocol + factory + resolver + EnvironmentKey
Muxy/Services/Vcs/GitStatusProbe.swift              - git impl
Muxy/Services/Vcs/JjStatusProbe.swift               - jj impl
Tests/MuxyTests/Services/Vcs/VcsStatusProbeTests.swift
```

Modified:
```
Muxy/Views/Sidebar/ExpandedProjectRow.swift   - resolver-based hasUncommittedChanges
Muxy/Views/Sidebar/WorktreePopover.swift      - resolver-based hasUncommittedChanges
```

---

### Task 1: VcsStatusProbe protocol + Git/Jj impls + resolver + EnvironmentKey

**Files:**
- Create: `Muxy/Services/Vcs/VcsStatusProbe.swift`
- Create: `Muxy/Services/Vcs/GitStatusProbe.swift`
- Create: `Muxy/Services/Vcs/JjStatusProbe.swift`
- Test: `Tests/MuxyTests/Services/Vcs/VcsStatusProbeTests.swift`

Combined into one task to avoid broken-build commit (same pattern as Phase 2.2b T1+T2+T3).

- [ ] **Step 1: Create the protocol + factory + resolver**

`Muxy/Services/Vcs/VcsStatusProbe.swift`:

```swift
import Foundation
import SwiftUI

protocol VcsStatusProbe: Sendable {
    func hasUncommittedChanges(at worktreePath: String) async -> Bool
}

enum VcsStatusProbeFactory {
    static func probe(for kind: VcsKind) -> any VcsStatusProbe {
        switch kind {
        case .git:
            return GitStatusProbe()
        case .jj:
            return JjStatusProbe()
        }
    }
}

struct VcsStatusProbeResolver: Sendable {
    private let resolve: @Sendable (VcsKind) -> any VcsStatusProbe

    init(_ resolve: @escaping @Sendable (VcsKind) -> any VcsStatusProbe) {
        self.resolve = resolve
    }

    func probe(_ kind: VcsKind) -> any VcsStatusProbe {
        resolve(kind)
    }

    static let `default` = VcsStatusProbeResolver { kind in
        VcsStatusProbeFactory.probe(for: kind)
    }
}

private struct VcsStatusProbeResolverKey: EnvironmentKey {
    static var defaultValue: VcsStatusProbeResolver { .default }
}

extension EnvironmentValues {
    var vcsStatusProbeResolver: VcsStatusProbeResolver {
        get { self[VcsStatusProbeResolverKey.self] }
        set { self[VcsStatusProbeResolverKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Create GitStatusProbe**

`Muxy/Services/Vcs/GitStatusProbe.swift`:

```swift
import Foundation

struct GitStatusProbe: VcsStatusProbe {
    func hasUncommittedChanges(at worktreePath: String) async -> Bool {
        await GitWorktreeService.shared.hasUncommittedChanges(worktreePath: worktreePath)
    }
}
```

- [ ] **Step 3: Create JjStatusProbe**

`Muxy/Services/Vcs/JjStatusProbe.swift`:

```swift
import Foundation
import MuxyShared

struct JjStatusProbe: VcsStatusProbe {
    private let probe: @Sendable (String) async -> Bool

    init(probe: @escaping @Sendable (String) async -> Bool = Self.defaultProbe) {
        self.probe = probe
    }

    func hasUncommittedChanges(at worktreePath: String) async -> Bool {
        await probe(worktreePath)
    }

    private static let defaultProbe: @Sendable (String) async -> Bool = { worktreePath in
        do {
            let result = try await JjProcessRunner.run(
                repoPath: worktreePath,
                command: ["status"],
                snapshot: .ignore
            )
            guard result.status == 0 else { return false }
            let raw = String(data: result.stdout, encoding: .utf8) ?? ""
            let status = try JjStatusParser.parse(raw)
            return !status.entries.isEmpty || status.hasConflicts
        } catch {
            return false
        }
    }
}
```

NOTE: jj's "dirty" semantics include both unsnapshotted file changes (filtered by `--ignore-working-copy`) AND files in the current change since last snapshot. With `--ignore-working-copy`, this returns the last-snapshotted state — fine for sidebar badge polling, doesn't race agents. User-triggered explicit snapshots (Save/Commit) are out of probe scope.

- [ ] **Step 4: Write tests**

`Tests/MuxyTests/Services/Vcs/VcsStatusProbeTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing

@testable import Roost

@Suite("VcsStatusProbe")
struct VcsStatusProbeTests {
    @Test("factory returns GitStatusProbe for .git")
    func factoryGit() {
        let probe = VcsStatusProbeFactory.probe(for: .git)
        #expect(probe is GitStatusProbe)
    }

    @Test("factory returns JjStatusProbe for .jj")
    func factoryJj() {
        let probe = VcsStatusProbeFactory.probe(for: .jj)
        #expect(probe is JjStatusProbe)
    }

    @Test("default resolver delegates to factory")
    func defaultResolves() {
        let resolver = VcsStatusProbeResolver.default
        #expect(resolver.probe(.git) is GitStatusProbe)
        #expect(resolver.probe(.jj) is JjStatusProbe)
    }

    @Test("custom resolver returns injected probe")
    func customResolver() {
        let stub = StatusProbeStub(answer: true)
        let resolver = VcsStatusProbeResolver { _ in stub }
        let probe = resolver.probe(.git)
        #expect(probe is StatusProbeStub)
    }

    @Test("JjStatusProbe with stubbed closure returns the stub answer")
    func jjStubbed() async {
        let probe = JjStatusProbe(probe: { _ in true })
        let result = await probe.hasUncommittedChanges(at: "/repo")
        #expect(result == true)
    }

    @Test("EnvironmentValues default is the default resolver")
    @MainActor
    func environmentDefault() {
        let env = EnvironmentValues()
        let resolver = env.vcsStatusProbeResolver
        #expect(resolver.probe(.git) is GitStatusProbe)
    }
}

final class StatusProbeStub: VcsStatusProbe, @unchecked Sendable {
    let answer: Bool
    init(answer: Bool) { self.answer = answer }
    func hasUncommittedChanges(at worktreePath: String) async -> Bool { answer }
}
```

- [ ] **Step 5: Build + test**

Run: `swift test --filter VcsStatusProbeTests`
Expected: 6/6 pass.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(vcs): VcsStatusProbe protocol + Git/Jj impls + resolver"
```

---

### Task 2: ExpandedProjectRow + WorktreePopover use resolver

**Files:**
- Modify: `Muxy/Views/Sidebar/ExpandedProjectRow.swift`
- Modify: `Muxy/Views/Sidebar/WorktreePopover.swift`

- [ ] **Step 1: ExpandedProjectRow**

Read `Muxy/Views/Sidebar/ExpandedProjectRow.swift` lines 1-60 to find existing `@Environment` declarations, then around line 341 for the call site.

Add `@Environment(\.vcsStatusProbeResolver) private var statusProbeResolver` near the existing `@Environment` declarations.

Replace line 341:
```swift
let hasChanges = await GitWorktreeService.shared.hasUncommittedChanges(worktreePath: worktree.path)
```
with:
```swift
let probe = statusProbeResolver.probe(worktree.vcsKind)
let hasChanges = await probe.hasUncommittedChanges(at: worktree.path)
```

The surrounding code in this view has access to `worktree` (a `Worktree` value), so `worktree.vcsKind` is in scope.

- [ ] **Step 2: WorktreePopover**

Same pattern. Read the file, add `@Environment(\.vcsStatusProbeResolver) private var statusProbeResolver`, replace line 89:
```swift
let hasChanges = await GitWorktreeService.shared.hasUncommittedChanges(worktreePath: worktree.path)
```
with:
```swift
let probe = statusProbeResolver.probe(worktree.vcsKind)
let hasChanges = await probe.hasUncommittedChanges(at: worktree.path)
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(sidebar): hasUncommittedChanges routes through VcsStatusProbeResolver"
```

---

### Task 3: Plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append**

After the Phase 2.2b2 status block, append:

```markdown

Phase 2.2c1 status (2026-04-28):

- `VcsStatusProbe` protocol + `GitStatusProbe` + `JjStatusProbe` + factory + `VcsStatusProbeResolver` (with SwiftUI environment key) added. Mirrors the controller-resolver pattern from Phase 2.2b2. Plan: `docs/superpowers/plans/2026-04-28-phase2-2c1-vcs-status-probe.md`.
- `ExpandedProjectRow` + `WorktreePopover` route `hasUncommittedChanges` through the resolver, dispatching by `worktree.vcsKind`. Behavior unchanged for git worktrees; jj worktrees now get a real status probe instead of an always-stale git answer.
- Phase 2.2c2/3 remains: `isGitRepository` callers, `VCSTabState.deleteBranch`, sidebar UI badges, `WorktreeDTO` IPC.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(vcs): note Phase 2.2c1 (VcsStatusProbe) landed"
```

---

## Self-Review

| Item | Covered by |
|------|-----------|
| Probe protocol | Task 1 |
| Git + Jj impls | Task 1 |
| Resolver + environment key | Task 1 |
| View callers routed | Task 2 |
| Tests | Task 1 |
| Doc | Task 3 |

Type consistency: `VcsStatusProbeResolver` mirrors `VcsWorktreeControllerResolver` shape. `worktree.vcsKind` lookup pattern identical at both call sites.

---

## Abort criteria

If `JjProcessRunner.run` is unavailable in the view target context (e.g., layering complaints), wrap the default jj probe in a free function and pass it as a closure rather than calling directly. The closure-injected design already supports this — `JjStatusProbe.init(probe:)` takes a custom closure.

If view builds break because `@Environment(\.vcsStatusProbeResolver)` isn't available where SwiftUI expects (rare; the env extension is in the same target), report BLOCKED with the exact compile error.
