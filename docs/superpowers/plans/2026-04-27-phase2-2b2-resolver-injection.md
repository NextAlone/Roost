# Phase 2.2b2 — VcsWorktreeControllerResolver injection

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Wire `VcsWorktreeController` into the two write-side production callers that aren't yet routed: `RemoteServerDelegate.vcsCreateWorktree` (init-param injection) and `CreateWorktreeSheet` (SwiftUI environment injection). Introduce a `VcsWorktreeControllerResolver` value type so consumers can hold a `VcsKind → controller` function rather than a single concrete controller. Defer `VCSTabState.deleteBranch` to a later plan because that class has 1000+ lines of git-coupled state and a piecemeal resolver insertion would leave inconsistent boundaries.

**Architecture:** `VcsWorktreeControllerResolver` is a `Sendable` value with a closure `(VcsKind) -> any VcsWorktreeController`. Default resolver delegates to `VcsWorktreeControllerFactory`. SwiftUI environment exposes the resolver via a custom `EnvironmentKey`. `CreateWorktreeSheet` reads it via `@Environment(\.vcsWorktreeControllerResolver)`, resolves with the project's primary `VcsKind` at call time, and stamps that `vcsKind` on the new `Worktree` it creates. `RemoteServerDelegate` accepts a resolver via its existing init (default `.default`); its `vcsCreateWorktree` looks up the project, asks the resolver for the right controller, and invokes `addWorktree`.

**Tech Stack:** Swift 6, swift-testing, SwiftUI environment.

**Out of scope (Phase 2.2c):**
- `VCSTabState.deleteBranch` controller routing — needs a broader VCSTabState VCS abstraction (read + write probes), planned separately.
- UI label changes (`branch` → `bookmark` for jj mode).
- Read-side probes (`isGitRepository`, `hasUncommittedChanges`).
- WorktreeDTO IPC update.

---

## File Structure

New:
```
Muxy/Services/Vcs/VcsWorktreeControllerResolver.swift
Tests/MuxyTests/Services/Vcs/VcsWorktreeControllerResolverTests.swift
```

Modified:
```
Muxy/Services/RemoteServerDelegate.swift           - init takes resolver, vcsCreateWorktree routes
Muxy/Views/Sidebar/CreateWorktreeSheet.swift       - @Environment resolver, route addWorktree, stamp vcsKind
Muxy/MuxyApp.swift                                  - pass .default resolver to RemoteServerDelegate (no behavior change)
```

---

## Conventions

- Internal-by-default. Resolver, environment key, and tests are `internal`.
- Tests: swift-testing.
- Project rule: no comments. jj-only VCS.
- After each commit: `swift test --filter "Vcs|Worktree|Jj"` should remain green.

---

### Task 1: VcsWorktreeControllerResolver + EnvironmentKey

**Files:**
- Create: `Muxy/Services/Vcs/VcsWorktreeControllerResolver.swift`
- Test: `Tests/MuxyTests/Services/Vcs/VcsWorktreeControllerResolverTests.swift`

- [ ] **Step 1: Write tests**

```swift
import Foundation
import SwiftUI
import Testing

@testable import Roost

@Suite("VcsWorktreeControllerResolver")
struct VcsWorktreeControllerResolverTests {
    @Test("default resolver delegates to factory")
    func defaultResolves() {
        let resolver = VcsWorktreeControllerResolver.default
        #expect(resolver.controller(.git) is GitWorktreeController)
        #expect(resolver.controller(.jj) is JjWorktreeController)
    }

    @Test("custom resolver returns injected controller")
    func customResolver() {
        let stub = StubController()
        let resolver = VcsWorktreeControllerResolver { _ in stub }
        #expect(resolver.controller(.git) as? StubController === stub)
        #expect(resolver.controller(.jj) as? StubController === stub)
    }

    @Test("EnvironmentValues default is the default resolver")
    @MainActor
    func environmentDefault() {
        let env = EnvironmentValues()
        let resolver = env.vcsWorktreeControllerResolver
        #expect(resolver.controller(.git) is GitWorktreeController)
    }
}

final class StubController: VcsWorktreeController, @unchecked Sendable {
    func addWorktree(repoPath: String, name: String, path: String, ref: String?, createRef: Bool) async throws {}
    func removeWorktree(repoPath: String, path: String, force: Bool) async throws {}
    func deleteRef(repoPath: String, name: String) async throws {}
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter VcsWorktreeControllerResolverTests`
Expected: compile error — `VcsWorktreeControllerResolver` undefined.

- [ ] **Step 3: Implement resolver + environment key**

Create `Muxy/Services/Vcs/VcsWorktreeControllerResolver.swift`:

```swift
import Foundation
import SwiftUI

struct VcsWorktreeControllerResolver: Sendable {
    private let resolve: @Sendable (VcsKind) -> any VcsWorktreeController

    init(_ resolve: @escaping @Sendable (VcsKind) -> any VcsWorktreeController) {
        self.resolve = resolve
    }

    func controller(_ kind: VcsKind) -> any VcsWorktreeController {
        resolve(kind)
    }

    static let `default` = VcsWorktreeControllerResolver { kind in
        VcsWorktreeControllerFactory.controller(for: kind)
    }
}

private struct VcsWorktreeControllerResolverKey: EnvironmentKey {
    static let defaultValue: VcsWorktreeControllerResolver = .default
}

extension EnvironmentValues {
    var vcsWorktreeControllerResolver: VcsWorktreeControllerResolver {
        get { self[VcsWorktreeControllerResolverKey.self] }
        set { self[VcsWorktreeControllerResolverKey.self] = newValue }
    }
}
```

NOTE: `EnvironmentKey.defaultValue` is `@MainActor`-isolated in modern Swift. If the compiler complains about `static let defaultValue: VcsWorktreeControllerResolver = .default` not being `Sendable`-safe in main-actor context, the resolver's `Sendable` conformance plus the constant value should satisfy. If it fails, switch the static let to a computed `static var` returning `.default` each access — slight cost, no functional difference.

- [ ] **Step 4: Run tests**

Run: `swift test --filter VcsWorktreeControllerResolverTests`
Expected: 3/3 pass.

Run: `swift build`
Expected: clean.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(vcs): VcsWorktreeControllerResolver + SwiftUI environment key"
```

---

### Task 2: RemoteServerDelegate routes through resolver

**Files:**
- Modify: `Muxy/Services/RemoteServerDelegate.swift`
- Modify: `Muxy/MuxyApp.swift` (construction site passes `.default`)

The existing init signature is `init(appState:projectStore:worktreeStore:)`. Add a 4th parameter `resolver: VcsWorktreeControllerResolver = .default`.

The `vcsCreateWorktree` site at line 455 hardcodes `GitWorktreeService.shared.addWorktree`. Replace with controller call. The project's `vcsKind` is determined by looking up its primary worktree: `worktreeStore.primary(for: project.id)?.vcsKind ?? .default`.

- [ ] **Step 1: Read context around line 455**

Read `Muxy/Services/RemoteServerDelegate.swift` lines 440-490 to see the full `vcsCreateWorktree` body and surrounding methods.

- [ ] **Step 2: Add resolver to init**

Add stored property and init param:

```swift
private let resolver: VcsWorktreeControllerResolver

init(
    appState: AppState,
    projectStore: ProjectStore,
    worktreeStore: WorktreeStore,
    resolver: VcsWorktreeControllerResolver = .default
) {
    self.appState = appState
    self.projectStore = projectStore
    self.worktreeStore = worktreeStore
    self.resolver = resolver
}
```

(Adapt to actual init body — read the file to see how the existing assignments are written.)

- [ ] **Step 3: Replace the addWorktree call**

At the `GitWorktreeService.shared.addWorktree(...)` call inside `vcsCreateWorktree`, change to:

```swift
let project = ... // existing lookup
let kind = await MainActor.run { worktreeStore.primary(for: project.id)?.vcsKind ?? .default }
let controller = resolver.controller(kind)
try await controller.addWorktree(
    repoPath: project.path,
    name: workspaceName,    // adapt to existing variable names
    path: worktreePath,     // adapt
    ref: branchName,        // adapt — could be nil
    createRef: createBranch // adapt
)
```

Read the existing call to see what variable names it uses (`workspaceName`, `worktreePath`, `branchName`, `createBranch` are guesses). Match the actual call site.

NOTE: If `worktreeStore` is `@MainActor`-isolated, the `primary(for:)` lookup must hop to the main actor (use `MainActor.run` or move logic).

- [ ] **Step 4: Update MuxyApp construction site**

Read `Muxy/MuxyApp.swift` around line 68 to see the existing `RemoteServerDelegate(...)` call. Add `resolver: .default` (or just rely on the default — the parameter has a default value, so no change needed in MuxyApp.swift if the call uses positional args without an explicit resolver). Verify the call still compiles.

- [ ] **Step 5: Build + tests**

Run: `swift build`
Expected: clean.

Run: `swift test`
Expected: existing tests still pass (RemoteServerDelegate has no unit tests typically; the change preserves behavior for `.git` projects).

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(vcs): RemoteServerDelegate.vcsCreateWorktree routes through resolver"
```

---

### Task 3: CreateWorktreeSheet uses environment resolver + stamps vcsKind

**Files:**
- Modify: `Muxy/Views/Sidebar/CreateWorktreeSheet.swift`

- [ ] **Step 1: Read the sheet**

Read `Muxy/Views/Sidebar/CreateWorktreeSheet.swift` lines 1-50 (already excerpted earlier — has `@Environment(WorktreeStore.self)` on line 24, `private let gitWorktree = GitWorktreeService.shared` on line 25). Read also lines 215-245 (the addWorktree call + Worktree construction).

- [ ] **Step 2: Replace gitWorktree property with environment resolver**

Replace line 25's `private let gitWorktree = GitWorktreeService.shared` with:

```swift
@Environment(\.vcsWorktreeControllerResolver) private var vcsResolver
```

Remove the `gitWorktree` property entirely.

- [ ] **Step 3: Route the addWorktree call**

At line ~218, replace:

```swift
try await gitWorktree.addWorktree(
    repoPath: project.path,
    path: worktreeDirectory,
    branch: branch,
    createBranch: createNewBranch
)
```

with:

```swift
let kind = worktreeStore.primary(for: project.id)?.vcsKind ?? .default
let controller = vcsResolver.controller(kind)
try await controller.addWorktree(
    repoPath: project.path,
    name: trimmedName,
    path: worktreeDirectory,
    ref: branch,
    createRef: createNewBranch
)
```

Use `trimmedName` (or whatever the local variable holding the entered worktree name is called — read the surrounding code).

- [ ] **Step 4: Stamp vcsKind on the new Worktree**

Below the controller call, the existing code constructs a `Worktree(...)`. Currently it doesn't pass `vcsKind`, so it defaults to `.git`. For jj projects this is wrong. Pass the resolved `kind`:

```swift
let worktree = Worktree(
    name: trimmedName,
    path: worktreeDirectory,
    branch: branch,
    ownsBranch: createNewBranch,
    isPrimary: false,
    vcsKind: kind
)
```

The existing `Worktree.init` already accepts `vcsKind:` with a default of `.default`, added in Phase 2.1. Just pass `vcsKind: kind`.

- [ ] **Step 5: Build**

Run: `swift build`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(sidebar): CreateWorktreeSheet routes addWorktree through resolver"
```

---

### Task 4: Plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append Phase 2.2b2 status block**

After the Phase 2.2b status note, append:

```markdown

Phase 2.2b2 status (2026-04-27):

- `VcsWorktreeControllerResolver` value type added; default resolver delegates to `VcsWorktreeControllerFactory`. SwiftUI exposes it via `EnvironmentValues.vcsWorktreeControllerResolver`. Plan: `docs/superpowers/plans/2026-04-27-phase2-2b2-resolver-injection.md`.
- `RemoteServerDelegate.vcsCreateWorktree` looks up the project's primary `VcsKind` and routes through the resolver. Init takes the resolver with `.default` fallback; `MuxyApp` construction is unchanged (default value).
- `CreateWorktreeSheet` reads the resolver via `@Environment(\.vcsWorktreeControllerResolver)`, dispatches `addWorktree` by the project's primary `vcsKind`, and stamps that kind on the newly created `Worktree`.
- Phase 2.2c remains: `VCSTabState.deleteBranch` and read-side probes (`isGitRepository`, `hasUncommittedChanges`) need a broader VCS abstraction; sidebar UI badges + `WorktreeDTO` IPC update also pending.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(vcs): note Phase 2.2b2 (resolver injection) landed"
```

---

## Self-Review

**Spec coverage:**

| Item | Covered by |
|------|-----------|
| Resolver value type | Task 1 |
| SwiftUI EnvironmentKey | Task 1 |
| RemoteServerDelegate routing | Task 2 |
| CreateWorktreeSheet routing + vcsKind stamp | Task 3 |

**Deferred (Phase 2.2c):**
- `VCSTabState.deleteBranch`
- Read-side probes
- UI label refinement

**Type consistency:** `VcsWorktreeControllerResolver` shape stable across producers (init injection, environment access). `vcsKind` lookup pattern (`primary(for:)?.vcsKind ?? .default`) used identically in both call sites.

**Placeholder scan:** No TODOs.

---

## Abort criteria

If `EnvironmentKey.defaultValue` triggers Sendable / @MainActor isolation errors that can't be resolved with the `static var` fallback, **stop**: drop the SwiftUI environment approach for `CreateWorktreeSheet` and pass the resolver via constructor (the sheet already takes `project` and `onFinish` — adding a third param is a small surface change, but it pollutes parent views that present the sheet). Report DONE_WITH_CONCERNS noting the deviation.

If `WorktreeStore.primary(for:)` returns nil during the create-worktree flow (which would mean no primary yet, unusual), **fall back** to `.default` (i.e., git) — this preserves prior behavior for any edge case where vcsKind isn't yet resolved.
