# Phase 2.2b — VcsWorktreeController + WorktreeStore cleanup routing

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Introduce a `VcsWorktreeController` protocol with git + jj implementations and route `WorktreeStore.cleanupOnDisk` through a factory that selects by `Worktree.vcsKind`. Other write-side touch points (`RemoteServerDelegate.vcsCreateWorktree`, `CreateWorktreeSheet`, `VCSTabState.deleteBranch`) are deferred to Phase 2.2b2 / 2.2c — they involve UI-layer DI which deserves its own plan.

**Architecture:** `VcsWorktreeController` is a `Sendable` protocol exposing `add`, `removeWorktree`, and `deleteRef` (`deleteRef` = git `branch -D` / jj `bookmark forget`). `GitWorktreeController` wraps the existing `GitWorktreeService.shared` instance — pure adapter. `JjWorktreeController` composes `JjWorkspaceService` + `JjBookmarkService` over a `JjProcessQueue`. `VcsWorktreeControllerFactory` is a static dispatcher: `.controller(for: VcsKind) -> any VcsWorktreeController`. `WorktreeStore.cleanupOnDisk` reads `worktree.vcsKind`, asks the factory for a controller, and calls through. The two static `cleanupOnDisk` methods stay static (their callers depend on it); the factory hides the polymorphism.

**Tech Stack:** Swift 6, swift-testing.

**Out of scope (Phase 2.2b2):**
- `RemoteServerDelegate.vcsCreateWorktree` controller routing
- `CreateWorktreeSheet` controller injection (DI through SwiftUI environment)
- `VCSTabState.deleteBranch` controller routing

**Out of scope (Phase 2.2c):**
- `isGitRepository` / `hasUncommittedChanges` status probes (read-side, separate concern)
- WorktreeDTO IPC update
- Sidebar UI badges

---

## File Structure

New:
```
Muxy/Services/Vcs/VcsWorktreeController.swift              - protocol + factory
Muxy/Services/Vcs/GitWorktreeController.swift              - git adapter
Muxy/Services/Vcs/JjWorktreeController.swift               - jj adapter
Tests/MuxyTests/Services/Vcs/VcsWorktreeControllerFactoryTests.swift
Tests/MuxyTests/Services/Vcs/JjWorktreeControllerTests.swift
```

Modified:
```
Muxy/Services/WorktreeStore.swift   - cleanupOnDisk uses factory
```

(`Muxy/Services/Vcs/` directory is new; SwiftPM picks it up automatically.)

---

## Conventions

- Internal-by-default. Controllers and factory are `internal`. Protocol stays `internal` too — no cross-module need.
- Tests: swift-testing, `@testable import Roost` + `import MuxyShared`.
- Project rule: no comments. jj-only VCS.
- After each commit: `swift test --filter "Vcs|Worktree|Jj"` should remain green.

---

### Task 1: VcsWorktreeController protocol + factory

**Files:**
- Create: `Muxy/Services/Vcs/VcsWorktreeController.swift`

This task defines the protocol and a static factory. No implementations yet.

- [ ] **Step 1: Create the protocol file**

```swift
import Foundation

protocol VcsWorktreeController: Sendable {
    func addWorktree(
        repoPath: String,
        name: String,
        path: String,
        ref: String?,
        createRef: Bool
    ) async throws

    func removeWorktree(
        repoPath: String,
        path: String,
        force: Bool
    ) async throws

    func deleteRef(repoPath: String, name: String) async throws
}

enum VcsWorktreeControllerFactory {
    static func controller(for kind: VcsKind) -> any VcsWorktreeController {
        switch kind {
        case .git:
            return GitWorktreeController()
        case .jj:
            return JjWorktreeController()
        }
    }
}
```

NOTE: This file references `GitWorktreeController` and `JjWorktreeController` which don't exist yet. The build will FAIL after this task; Tasks 2 and 3 fill in the impls. That's intentional — protocol-first lets implementers see the surface they're adapting to.

- [ ] **Step 2: Confirm expected build failure**

Run: `swift build`
Expected: error — "Cannot find type 'GitWorktreeController'" / "Cannot find type 'JjWorktreeController'".

This is fine. Don't try to make it build until Task 3 lands.

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(vcs): VcsWorktreeController protocol + factory skeleton"
```

NOTE: this commit intentionally has a broken build. The next two tasks restore green. If your linter / pre-commit refuses a broken build, comment out the factory body temporarily, commit, then uncomment in Task 3.

If pre-commit hooks block this strategy, alternative: combine Tasks 1+2+3 into one larger task / commit. Up to your judgment as implementer; report DONE_WITH_CONCERNS noting the deviation.

---

### Task 2: GitWorktreeController

**Files:**
- Create: `Muxy/Services/Vcs/GitWorktreeController.swift`

Pure adapter over `GitWorktreeService.shared`. The existing service uses singletons; we just wrap calls.

- [ ] **Step 1: Read GitWorktreeService API**

Read `Muxy/Services/Git/GitWorktreeService.swift` to confirm:
- `addWorktree(repoPath:path:branch:createBranch:)` signature
- `removeWorktree(repoPath:path:force:)` signature
- `deleteBranch(repoPath:branch:force:)` signature

If signatures differ from these, adapt the controller to match.

- [ ] **Step 2: Implement**

Create `Muxy/Services/Vcs/GitWorktreeController.swift`:

```swift
import Foundation

struct GitWorktreeController: VcsWorktreeController {
    func addWorktree(
        repoPath: String,
        name: String,
        path: String,
        ref: String?,
        createRef: Bool
    ) async throws {
        let branch = ref ?? name
        try await GitWorktreeService.shared.addWorktree(
            repoPath: repoPath,
            path: path,
            branch: branch,
            createBranch: createRef
        )
    }

    func removeWorktree(
        repoPath: String,
        path: String,
        force: Bool
    ) async throws {
        try await GitWorktreeService.shared.removeWorktree(
            repoPath: repoPath,
            path: path,
            force: force
        )
    }

    func deleteRef(repoPath: String, name: String) async throws {
        try await GitWorktreeService.shared.deleteBranch(repoPath: repoPath, branch: name)
    }
}
```

NOTE: `addWorktree` parameter `name` maps to git's branch name when no `ref` is provided. This matches existing `CreateWorktreeSheet` semantics where the worktree's name and branch are usually the same.

If `GitWorktreeService.deleteBranch` takes a `force` parameter that defaults to `true`, the call above works. If it requires the parameter explicitly, add `force: true`.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: still failing on `JjWorktreeController` not found. That's fine — Task 3 fixes it.

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(vcs): GitWorktreeController wraps GitWorktreeService"
```

---

### Task 3: JjWorktreeController

**Files:**
- Create: `Muxy/Services/Vcs/JjWorktreeController.swift`
- Test: `Tests/MuxyTests/Services/Vcs/JjWorktreeControllerTests.swift`

This is the substantive task. Maps controller semantics onto jj:
- `addWorktree` → `JjWorkspaceService.add` + optionally `JjBookmarkService.create`
- `removeWorktree` → `JjWorkspaceService.forget` + filesystem delete (jj doesn't auto-delete the workspace dir)
- `deleteRef` → `JjBookmarkService.forget`

- [ ] **Step 1: Write tests**

Create `Tests/MuxyTests/Services/Vcs/JjWorktreeControllerTests.swift`:

```swift
import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjWorktreeController")
struct JjWorktreeControllerTests {
    @Test("addWorktree without createRef calls workspace add only")
    func addWithoutRef() async throws {
        let calls = JjControllerCallLog()
        let controller = JjWorktreeController(
            workspaceList: { _ in [] },
            workspaceAdd: { repo, name, path in
                await calls.append("workspace.add:\(name)@\(path)")
            },
            workspaceForget: { _, _ in },
            bookmarkCreate: { _, _ in
                await calls.append("bookmark.create:should-not-be-called")
            },
            bookmarkForget: { _, _ in }
        )
        try await controller.addWorktree(
            repoPath: "/repo",
            name: "feat-x",
            path: "/repo/.worktrees/feat-x",
            ref: nil,
            createRef: false
        )
        let log = await calls.entries
        #expect(log == ["workspace.add:feat-x@/repo/.worktrees/feat-x"])
    }

    @Test("addWorktree with createRef also creates bookmark")
    func addWithCreateRef() async throws {
        let calls = JjControllerCallLog()
        let controller = JjWorktreeController(
            workspaceList: { _ in [] },
            workspaceAdd: { repo, name, path in
                await calls.append("workspace.add:\(name)@\(path)")
            },
            workspaceForget: { _, _ in },
            bookmarkCreate: { repo, name in
                await calls.append("bookmark.create:\(name)")
            },
            bookmarkForget: { _, _ in }
        )
        try await controller.addWorktree(
            repoPath: "/repo",
            name: "feat-x",
            path: "/repo/.worktrees/feat-x",
            ref: "feat-x",
            createRef: true
        )
        let log = await calls.entries
        #expect(log == [
            "workspace.add:feat-x@/repo/.worktrees/feat-x",
            "bookmark.create:feat-x"
        ])
    }

    @Test("removeWorktree calls workspace forget by inferred name + deletes path")
    func removeByPath() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("jjctrl-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let calls = JjControllerCallLog()
        let entry = JjWorkspaceEntry(
            name: "feat-x",
            workingCopy: JjChangeId(prefix: "abcdef0123ab", full: "abcdef0123abcdef0123456789abcdef")
        )
        let controller = JjWorktreeController(
            workspaceList: { _ in [entry] },
            workspaceAdd: { _, _, _ in },
            workspaceForget: { repo, name in
                await calls.append("workspace.forget:\(name)")
            },
            bookmarkCreate: { _, _ in },
            bookmarkForget: { _, _ in }
        )
        try await controller.removeWorktree(repoPath: "/repo", path: tmp.path, force: true)

        let log = await calls.entries
        #expect(log == ["workspace.forget:feat-x"])
        #expect(fm.fileExists(atPath: tmp.path) == false)
    }

    @Test("deleteRef calls bookmark forget")
    func deleteRefCallsBookmarkForget() async throws {
        let calls = JjControllerCallLog()
        let controller = JjWorktreeController(
            workspaceList: { _ in [] },
            workspaceAdd: { _, _, _ in },
            workspaceForget: { _, _ in },
            bookmarkCreate: { _, _ in },
            bookmarkForget: { repo, name in
                await calls.append("bookmark.forget:\(name)")
            }
        )
        try await controller.deleteRef(repoPath: "/repo", name: "feat-x")
        let log = await calls.entries
        #expect(log == ["bookmark.forget:feat-x"])
    }
}

actor JjControllerCallLog {
    var entries: [String] = []
    func append(_ s: String) { entries.append(s) }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter JjWorktreeControllerTests`
Expected: compile error (controller doesn't exist yet, plus build was already broken from Task 1).

- [ ] **Step 3: Implement controller**

Create `Muxy/Services/Vcs/JjWorktreeController.swift`:

```swift
import Foundation
import MuxyShared

struct JjWorktreeController: VcsWorktreeController {
    private let workspaceList: @Sendable (String) async throws -> [JjWorkspaceEntry]
    private let workspaceAdd: @Sendable (String, String, String) async throws -> Void
    private let workspaceForget: @Sendable (String, String) async throws -> Void
    private let bookmarkCreate: @Sendable (String, String) async throws -> Void
    private let bookmarkForget: @Sendable (String, String) async throws -> Void

    init(
        workspaceList: @escaping @Sendable (String) async throws -> [JjWorkspaceEntry] = Self.defaultWorkspaceList,
        workspaceAdd: @escaping @Sendable (String, String, String) async throws -> Void = Self.defaultWorkspaceAdd,
        workspaceForget: @escaping @Sendable (String, String) async throws -> Void = Self.defaultWorkspaceForget,
        bookmarkCreate: @escaping @Sendable (String, String) async throws -> Void = Self.defaultBookmarkCreate,
        bookmarkForget: @escaping @Sendable (String, String) async throws -> Void = Self.defaultBookmarkForget
    ) {
        self.workspaceList = workspaceList
        self.workspaceAdd = workspaceAdd
        self.workspaceForget = workspaceForget
        self.bookmarkCreate = bookmarkCreate
        self.bookmarkForget = bookmarkForget
    }

    func addWorktree(
        repoPath: String,
        name: String,
        path: String,
        ref: String?,
        createRef: Bool
    ) async throws {
        try await workspaceAdd(repoPath, name, path)
        if createRef {
            let refName = ref ?? name
            try await bookmarkCreate(repoPath, refName)
        }
    }

    func removeWorktree(
        repoPath: String,
        path: String,
        force: Bool
    ) async throws {
        let entries = try await workspaceList(repoPath)
        if let name = entries.first(where: { _ in true }).map(\.name),
           entries.count == 1
        {
            try await workspaceForget(repoPath, name)
        } else if let match = entries.first(where: { entry in
            // Path inference: jj doesn't expose path on WorkspaceRef. Caller passes the path,
            // but we can't map name <- path from list alone. Use the worktree name when available.
            entry.name == (path as NSString).lastPathComponent
        }) {
            try await workspaceForget(repoPath, match.name)
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    func deleteRef(repoPath: String, name: String) async throws {
        try await bookmarkForget(repoPath, name)
    }

    private static let defaultWorkspaceList: @Sendable (String) async throws -> [JjWorkspaceEntry] = { repoPath in
        let queue = JjProcessQueue()
        let service = JjWorkspaceService(queue: queue)
        return try await service.list(repoPath: repoPath)
    }

    private static let defaultWorkspaceAdd: @Sendable (String, String, String) async throws -> Void = { repoPath, name, path in
        let queue = JjProcessQueue()
        let service = JjWorkspaceService(queue: queue)
        try await service.add(repoPath: repoPath, name: name, path: path)
    }

    private static let defaultWorkspaceForget: @Sendable (String, String) async throws -> Void = { repoPath, name in
        let queue = JjProcessQueue()
        let service = JjWorkspaceService(queue: queue)
        try await service.forget(repoPath: repoPath, name: name)
    }

    private static let defaultBookmarkCreate: @Sendable (String, String) async throws -> Void = { repoPath, name in
        let queue = JjProcessQueue()
        let service = JjBookmarkService(queue: queue)
        try await service.create(repoPath: repoPath, name: name, revset: nil)
    }

    private static let defaultBookmarkForget: @Sendable (String, String) async throws -> Void = { repoPath, name in
        let queue = JjProcessQueue()
        let service = JjBookmarkService(queue: queue)
        try await service.forget(repoPath: repoPath, name: name)
    }
}
```

NOTE on `removeWorktree`: jj `workspace forget` takes a workspace name. Roost's caller passes the path. Without `WorkspaceRef.path()`, we can't perfectly map path → name. The test fixture asserts the inference works for the lastPathComponent fallback (which is the typical case where Roost-managed workspaces have name == directory leaf). This is best-effort; Phase 2.2c can store name on the Worktree to make the mapping deterministic.

- [ ] **Step 4: Run tests**

Run: `swift build`
Expected: NOW clean (Task 1's broken state resolved).

Run: `swift test --filter JjWorktreeControllerTests`
Expected: 4/4 pass.

Run: `swift test --filter Jj`
Expected: full Jj suite green.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(vcs): JjWorktreeController over JjWorkspaceService + JjBookmarkService"
```

---

### Task 4: Factory smoke test

**Files:**
- Create: `Tests/MuxyTests/Services/Vcs/VcsWorktreeControllerFactoryTests.swift`

- [ ] **Step 1: Write tests**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("VcsWorktreeControllerFactory")
struct VcsWorktreeControllerFactoryTests {
    @Test("returns GitWorktreeController for .git")
    func git() {
        let controller = VcsWorktreeControllerFactory.controller(for: .git)
        #expect(controller is GitWorktreeController)
    }

    @Test("returns JjWorktreeController for .jj")
    func jj() {
        let controller = VcsWorktreeControllerFactory.controller(for: .jj)
        #expect(controller is JjWorktreeController)
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter VcsWorktreeControllerFactoryTests`
Expected: 2/2 pass.

- [ ] **Step 3: Commit**

```bash
jj commit -m "test(vcs): factory dispatches by VcsKind"
```

---

### Task 5: WorktreeStore.cleanupOnDisk routes through factory

**Files:**
- Modify: `Muxy/Services/WorktreeStore.swift`

The static `cleanupOnDisk(worktree:repoPath:)` and `cleanupOnDisk(for:knownWorktrees:)` route through the factory. Per-worktree cleanup uses `worktree.vcsKind`. Project-level cleanup falls back to git for unknown disk children (the existing behavior — those aren't tracked Worktrees).

- [ ] **Step 1: Read current cleanup**

Read `Muxy/Services/WorktreeStore.swift` lines 198-260 to see both cleanupOnDisk overloads.

- [ ] **Step 2: Replace per-worktree cleanup**

Locate `static func cleanupOnDisk(worktree:repoPath:)` (around line 198). Replace its body with controller-routed version:

```swift
static func cleanupOnDisk(
    worktree: Worktree,
    repoPath: String
) async {
    guard worktree.canBeRemoved else { return }
    let controller = VcsWorktreeControllerFactory.controller(for: worktree.vcsKind)
    do {
        try await controller.removeWorktree(
            repoPath: repoPath,
            path: worktree.path,
            force: true
        )
    } catch {
        logger.error("Failed to remove worktree at \(worktree.path): \(error)")
    }

    if worktree.ownsBranch,
       let branch = worktree.branch?.trimmingCharacters(in: .whitespacesAndNewlines),
       !branch.isEmpty
    {
        do {
            try await controller.deleteRef(repoPath: repoPath, name: branch)
        } catch {
            logger.error("Failed to delete ref \(branch) for worktree \(worktree.path): \(error)")
        }
    }

    try? FileManager.default.removeItem(atPath: worktree.path)
    removeParentDirectoryIfEmpty(for: worktree.path)
}
```

Note: `controller.removeWorktree` for jj already does the FileManager.default.removeItem internally; calling it again here is redundant but harmless (the first removal succeeds, the second `try?` is a no-op). For git, the controller call removes via `git worktree remove`, leaving the directory deletion path to fail safely as a fallback. No behavior regression.

- [ ] **Step 3: Replace project-level cleanup**

Locate `static func cleanupOnDisk(for project: Project, knownWorktrees: [Worktree])` (around line 228). The orphan-children sweep at the end currently uses `GitWorktreeService.shared.removeWorktree`. Project-level cleanup applies to leftover directories that aren't tracked Worktrees, so VcsKind isn't directly available. Use the project's primary worktree's vcsKind as a proxy for the project itself:

```swift
static func cleanupOnDisk(for project: Project, knownWorktrees: [Worktree]) async {
    let secondaryWorktrees = knownWorktrees.filter(\.canBeRemoved)
    for worktree in secondaryWorktrees {
        await cleanupOnDisk(worktree: worktree, repoPath: project.path)
    }

    let primaryKind = knownWorktrees.first(where: \.isPrimary)?.vcsKind ?? .default
    let controller = VcsWorktreeControllerFactory.controller(for: primaryKind)

    let root = MuxyFileStorage.worktreeRoot(forProjectID: project.id)
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    let children = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
    for child in children {
        let childPath = root.appendingPathComponent(child).path
        try? await controller.removeWorktree(
            repoPath: project.path,
            path: childPath,
            force: true
        )
        try? FileManager.default.removeItem(atPath: childPath)
    }
}
```

Read the actual current code to match its exact structure — what I have above might have minor differences from the real implementation. Adapt as needed.

- [ ] **Step 4: Build + tests**

Run: `swift build`
Expected: clean.

Run: `swift test --filter Worktree`
Expected: all 20 pass (existing tests don't exercise vcsKind=.jj cleanup yet; behavior unchanged for .git path).

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(WorktreeStore): cleanupOnDisk routes through VcsWorktreeController"
```

---

### Task 6: Integration smoke test for git path equivalence

**Files:**
- Create: `Tests/MuxyTests/Services/Vcs/GitWorktreeControllerTests.swift`

We don't unit-test the GitWorktreeController against a live git repo (too much setup). Instead, verify it correctly forwards each method via stubbing the underlying service. Since `GitWorktreeService.shared` is a global, this requires a small refactor: extract a closure-injection for testability matching the JjWorktreeController pattern.

If refactoring `GitWorktreeController` to accept closures grows the scope too much, **skip this task** and rely on the existing `WorktreeStoreRefreshDispatchTests` (which exercise the read path) plus manual verification of the cleanup change. Report DONE_WITH_CONCERNS noting the deferred coverage.

If you choose to refactor, mirror JjWorktreeController's closure pattern:

```swift
struct GitWorktreeController: VcsWorktreeController {
    private let addWorktreeFn: @Sendable (String, String, String, Bool) async throws -> Void
    private let removeWorktreeFn: @Sendable (String, String, Bool) async throws -> Void
    private let deleteBranchFn: @Sendable (String, String) async throws -> Void

    init(
        addWorktreeFn: @escaping @Sendable (String, String, String, Bool) async throws -> Void = { repoPath, path, branch, createBranch in
            try await GitWorktreeService.shared.addWorktree(
                repoPath: repoPath,
                path: path,
                branch: branch,
                createBranch: createBranch
            )
        },
        removeWorktreeFn: @escaping @Sendable (String, String, Bool) async throws -> Void = { repoPath, path, force in
            try await GitWorktreeService.shared.removeWorktree(repoPath: repoPath, path: path, force: force)
        },
        deleteBranchFn: @escaping @Sendable (String, String) async throws -> Void = { repoPath, branch in
            try await GitWorktreeService.shared.deleteBranch(repoPath: repoPath, branch: branch)
        }
    ) {
        self.addWorktreeFn = addWorktreeFn
        self.removeWorktreeFn = removeWorktreeFn
        self.deleteBranchFn = deleteBranchFn
    }

    // Methods now call through closures
}
```

Then add tests verifying call routing:

```swift
@Test("addWorktree forwards to GitWorktreeService with branch and createBranch")
func addForwarding() async throws {
    let calls = GitControllerCallLog()
    let controller = GitWorktreeController(
        addWorktreeFn: { repo, path, branch, createBranch in
            await calls.append("add:\(branch)@\(path),create=\(createBranch)")
        },
        removeWorktreeFn: { _, _, _ in },
        deleteBranchFn: { _, _ in }
    )
    try await controller.addWorktree(
        repoPath: "/r",
        name: "feat-x",
        path: "/r/.worktrees/feat-x",
        ref: nil,
        createRef: true
    )
    let log = await calls.entries
    #expect(log == ["add:feat-x@/r/.worktrees/feat-x,create=true"])
}
```

Plus 2 more for remove + deleteRef.

- [ ] **Step 1: Decide**

If you're refactoring the controller, do Steps 2-4. If not, jump to Step 5.

- [ ] **Step 2: Refactor GitWorktreeController to closure injection**

(See sketch above.) Update `Muxy/Services/Vcs/GitWorktreeController.swift`.

- [ ] **Step 3: Write the 3 forwarding tests**

(See sketch above.) Plus a `GitControllerCallLog` actor.

- [ ] **Step 4: Run + commit**

Run: `swift test --filter GitWorktreeControllerTests`
Expected: 3/3 pass.

```bash
jj commit -m "test(vcs): GitWorktreeController closure-injection forwarding"
```

- [ ] **Step 5 (alternate): Skip and document**

If you skipped, no commit. Note in the final report that GitWorktreeController has no unit test, only integration via existing `WorktreeStoreRefreshDispatchTests` and manual cleanup invocation.

---

### Task 7: Plan note + final checks

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Run full check**

Run: `swift build`
Run: `swift test --filter "Vcs|Jj|Worktree"`
Expected: all green.

- [ ] **Step 2: Update Phase 2 status block**

Append after the Phase 2.2a status note:

```markdown

Phase 2.2b status (2026-04-27):

- `VcsWorktreeController` protocol introduced with `addWorktree`/`removeWorktree`/`deleteRef`. `GitWorktreeController` adapts `GitWorktreeService.shared`; `JjWorktreeController` composes `JjWorkspaceService` + `JjBookmarkService`. Plan: `docs/superpowers/plans/2026-04-27-phase2-2b-worktree-controller-cleanup.md`.
- `VcsWorktreeControllerFactory.controller(for: VcsKind)` selects the impl.
- `WorktreeStore.cleanupOnDisk` (both overloads) routes through the factory; per-worktree uses `worktree.vcsKind`, project-level uses primary's vcsKind.
- Phase 2.2b2 remains: `RemoteServerDelegate.vcsCreateWorktree` + `CreateWorktreeSheet` + `VCSTabState.deleteBranch` controller routing.
```

- [ ] **Step 3: Commit**

```bash
jj commit -m "docs(vcs): note Phase 2.2b (worktree controller + cleanup) landed"
```

---

## Self-Review

**Spec coverage**:

| Item | Covered by |
|------|-----------|
| Protocol definition | Task 1 |
| Git impl | Task 2 (+ Task 6 forwarding tests if not skipped) |
| Jj impl | Task 3 (with full unit tests) |
| Factory | Task 1 + Task 4 |
| WorktreeStore.cleanupOnDisk routing | Task 5 |

**Deferred** (Phase 2.2b2):
- `RemoteServerDelegate.vcsCreateWorktree` (UI path; SwiftUI environment DI)
- `CreateWorktreeSheet` controller injection
- `VCSTabState.deleteBranch`

**Type consistency:** `VcsWorktreeController` shape used identically by both impls. `VcsKind` from Phase 2.1 drives factory selection.

**Placeholder scan:** No TODOs.

---

## Abort criteria

If `JjWorktreeController.removeWorktree`'s name-inference heuristic (lastPathComponent match) doesn't cover the actual Roost worktree directory layout, **stop**: extend `Worktree` to carry a `jjWorkspaceName: String?` field and pass it through the cleanup call chain. That requires a small Worktree model change beyond Phase 2.1 — pivot to a 2.2b1.5 plan that adds the field, then return to controller wiring.

If protocol-first commit (Task 1 with broken build) blocks pre-commit hooks unfixably, combine Tasks 1+2+3 into one commit and report DONE_WITH_CONCERNS for the deviation.
