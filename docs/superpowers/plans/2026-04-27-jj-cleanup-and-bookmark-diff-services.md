# jj Service Layer — Cleanup + Bookmark/Diff/Show Services

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Pay down the Important design debt flagged in the foundation final review, then complete Phase 1 remaining services (bookmark, diff, show) on the cleaned interface so Phase 2 worktree adapter can ride on a stable surface.

**Architecture:** Refactor first (3 tasks): make `JjProcessQueue.run` a throwing generic so callers can return values + propagate errors directly (kills the `ErrorBox` workaround); centralize `JjRunFn` typealias in `JjProcessRunner.swift` so service files don't depend on each other; normalize parameter labels to `repoPath:`; narrow `public` to `internal` for everything outside `MuxyShared/Jj`. Then add three small services following the cleaned pattern: `JjBookmarkParser` + `JjBookmarkService` (list/create/forget/set), `JjDiffParser` + `JjDiffService` (`--stat` + `--summary`), and a `show` method on `JjRepositoryService`. Tests stay fixture-driven for parsers + closure-injected for services.

**Tech Stack:** Swift 6, swift-testing, jj ≥ 0.20 (validated against 0.40 in repo).

**Out of scope (separate plans):**
- Phase 2 Worktree → JjWorkspace adapter
- Hostd, sidebar UI, Changes panel
- jj operation log UI / undo
- Conflict content viewer

---

## File Structure

Modified:
```
Muxy/Services/Jj/JjProcessRunner.swift   - host JjRunFn typealias
Muxy/Services/Jj/JjProcessQueue.swift    - run<T> throwing generic
Muxy/Services/Jj/JjRepositoryService.swift - drop JjRunFn def, normalize repoPath, add show
Muxy/Services/Jj/JjWorkspaceService.swift - drop ErrorBox, use throwing run
Muxy/Services/Jj/JjStatusParser.swift    - access narrowed
Muxy/Services/Jj/JjOpLogParser.swift     - access narrowed
Muxy/Services/Jj/JjConflictParser.swift  - access narrowed
Muxy/Services/Jj/JjWorkspaceParser.swift - access narrowed
Muxy/Services/Jj/JjVersion.swift         - access narrowed (extension stays internal-by-default; minimumSupported stays accessible)
```

New:
```
Muxy/Services/Jj/JjBookmarkParser.swift
Muxy/Services/Jj/JjBookmarkService.swift
Muxy/Services/Jj/JjDiffParser.swift
Muxy/Services/Jj/JjDiffService.swift
Tests/MuxyTests/Jj/JjBookmarkParserTests.swift
Tests/MuxyTests/Jj/JjBookmarkServiceTests.swift
Tests/MuxyTests/Jj/JjDiffParserTests.swift
Tests/MuxyTests/Jj/JjDiffServiceTests.swift
```

Test files updated for repoPath: rename:
```
Tests/MuxyTests/Jj/JjRepositoryServiceTests.swift
Tests/MuxyTests/Jj/JjWorkspaceServiceTests.swift
```

DTO additions in `MuxyShared/Jj/JjModels.swift`:
- `JjDiffStat` (Sendable, Codable): files: [JjDiffFileStat], totalAdditions: Int, totalDeletions: Int
- `JjDiffFileStat` (Sendable, Codable): path: String, additions: Int, deletions: Int
- `JjShowOutput` (Sendable, Codable): change: JjChangeId, parents: [JjChangeId], description: String, diffStat: JjDiffStat?

---

## Conventions

- All new internal-by-default; `public` only on DTOs in MuxyShared and on the typealias `JjRunFn` (so external test fixtures can build their own runners).
- Tests: swift-testing (`@Suite`/`@Test`/`#expect`), `@testable import Roost` + `import MuxyShared`.
- After every commit step, run `scripts/checks.sh --fix` (informational; passes locally only when swiftformat/swiftlint installed).
- Real jj fixtures captured from jj 0.40 (already validated in foundation).
- jj-only VCS: never run `git`. Use `jj commit -m "..."` for each step.

---

### Task 1: JjProcessQueue throwing generic + remove ErrorBox

**Files:**
- Modify: `Muxy/Services/Jj/JjProcessQueue.swift`
- Modify: `Muxy/Services/Jj/JjWorkspaceService.swift` (drop ErrorBox actor)
- Modify: `Tests/MuxyTests/Jj/JjProcessQueueTests.swift`

- [ ] **Step 1: Update JjProcessQueueTests for throwing generic**

Edit `Tests/MuxyTests/Jj/JjProcessQueueTests.swift` to use the new signature. Replace test bodies with these (keep imports + suite + Log helper):

```swift
@Test("mutating operations on same repo are serialized")
func serializesMutating() async throws {
    let queue = JjProcessQueue()
    let log = Log()
    async let a: Void = try queue.run(repoPath: "/repo", isMutating: true) {
        await log.append("a-start")
        try? await Task.sleep(nanoseconds: 50_000_000)
        await log.append("a-end")
    }
    async let b: Void = try queue.run(repoPath: "/repo", isMutating: true) {
        await log.append("b-start")
        await log.append("b-end")
    }
    _ = try await (a, b)
    let entries = await log.entries
    #expect(entries == ["a-start", "a-end", "b-start", "b-end"]
        || entries == ["b-start", "b-end", "a-start", "a-end"])
}

@Test("read operations run concurrently")
func readsConcurrent() async throws {
    let queue = JjProcessQueue()
    let log = Log()
    async let a: Void = try queue.run(repoPath: "/repo", isMutating: false) {
        await log.append("a-start")
        try? await Task.sleep(nanoseconds: 50_000_000)
        await log.append("a-end")
    }
    async let b: Void = try queue.run(repoPath: "/repo", isMutating: false) {
        await log.append("b-start")
        await log.append("b-end")
    }
    _ = try await (a, b)
    let entries = await log.entries
    #expect(entries.firstIndex(of: "b-start")! < entries.firstIndex(of: "a-end")!)
}

@Test("returns body's value")
func returnsValue() async throws {
    let queue = JjProcessQueue()
    let value = try await queue.run(repoPath: "/r", isMutating: true) { 42 }
    #expect(value == 42)
}

@Test("propagates errors from body")
func propagatesError() async {
    let queue = JjProcessQueue()
    struct Boom: Error {}
    await #expect(throws: Boom.self) {
        try await queue.run(repoPath: "/r", isMutating: true) { throw Boom() }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter JjProcessQueueTests`
Expected: compile error — current `run` returns `Void` non-throwing.

- [ ] **Step 3: Rewrite JjProcessQueue to throwing generic**

Replace contents of `Muxy/Services/Jj/JjProcessQueue.swift`:

```swift
import Foundation

actor JjProcessQueue {
    private var inflight: [String: Task<Void, Never>] = [:]

    init() {}

    func run<T: Sendable>(
        repoPath: String,
        isMutating: Bool,
        body: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        if !isMutating {
            return try await body()
        }
        let previous = inflight[repoPath]
        let resultBox = ResultBox<T>()
        let task = Task {
            await previous?.value
            do {
                let value = try await body()
                await resultBox.set(.success(value))
            } catch {
                await resultBox.set(.failure(error))
            }
        }
        inflight[repoPath] = task
        await task.value
        if inflight[repoPath] == task {
            inflight[repoPath] = nil
        }
        return try await resultBox.value()
    }
}

private actor ResultBox<T: Sendable> {
    private var stored: Result<T, Error>?

    func set(_ result: Result<T, Error>) {
        stored = result
    }

    func value() throws -> T {
        guard let stored else {
            throw JjProcessQueueError.bodyDidNotRun
        }
        return try stored.get()
    }
}

enum JjProcessQueueError: Error, Sendable {
    case bodyDidNotRun
}
```

- [ ] **Step 4: Drop ErrorBox + use new run signature in JjWorkspaceService**

Replace `runMutating` body in `Muxy/Services/Jj/JjWorkspaceService.swift` and remove the trailing `private actor ErrorBox`. Final file:

```swift
import Foundation
import MuxyShared

struct JjWorkspaceService: Sendable {
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

    func list(repoPath: String) async throws -> [JjWorkspaceEntry] {
        let result = try await runner(repoPath, ["workspace", "list"], .ignore, nil)
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjWorkspaceParser.parse(raw)
    }

    func add(repoPath: String, name: String, path: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["workspace", "add", "--name", name, path])
    }

    func forget(repoPath: String, name: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["workspace", "forget", name])
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

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter JjProcessQueueTests`
Expected: 4/4 pass (2 original + 2 new for return value + error propagation).

Run: `swift test --filter JjWorkspaceServiceTests`
Expected: 3/3 still pass.

- [ ] **Step 6: Commit**

```bash
jj commit -m "refactor(jj): JjProcessQueue throwing generic, drop ErrorBox"
```

---

### Task 2: Relocate JjRunFn to runner + normalize repoPath labels

**Files:**
- Modify: `Muxy/Services/Jj/JjProcessRunner.swift` (add `JjRunFn` typealias)
- Modify: `Muxy/Services/Jj/JjRepositoryService.swift` (drop typealias def, rename `path:` → `repoPath:`)
- Modify: `Tests/MuxyTests/Jj/JjRepositoryServiceTests.swift` (call sites use `repoPath:`)

- [ ] **Step 1: Update test call sites first (TDD: test surface change)**

Edit `Tests/MuxyTests/Jj/JjRepositoryServiceTests.swift`. Replace every `svc.isJjRepo(path: "/repo")` / `svc.version(path: "/repo")` / `svc.currentOpId(path: "/repo")` with `repoPath:` keyword. Whole file:

```swift
import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjRepositoryService")
struct JjRepositoryServiceTests {
    @Test("isJjRepo true on success")
    func isRepoTrue() async throws {
        let svc = JjRepositoryService { _, _, _, _ in
            JjProcessResult(status: 0, stdout: Data("/repo\n".utf8), stderr: "")
        }
        #expect(try await svc.isJjRepo(repoPath: "/repo"))
    }

    @Test("isJjRepo false on non-zero exit")
    func isRepoFalse() async throws {
        let svc = JjRepositoryService { _, _, _, _ in
            JjProcessResult(status: 1, stdout: Data(), stderr: "no jj repo")
        }
        #expect(try await svc.isJjRepo(repoPath: "/repo") == false)
    }

    @Test("version parses runner output")
    func version() async throws {
        let svc = JjRepositoryService { _, _, _, _ in
            JjProcessResult(status: 0, stdout: Data("jj 0.40.0\n".utf8), stderr: "")
        }
        let v = try await svc.version()
        #expect(v == JjVersion(major: 0, minor: 40, patch: 0))
    }

    @Test("currentOpId parses op log")
    func currentOp() async throws {
        let svc = JjRepositoryService { _, _, _, _ in
            JjProcessResult(
                status: 0,
                stdout: Data("abc1234\t2026-04-27T10:15:30+00:00\tcommit\n".utf8),
                stderr: ""
            )
        }
        let op = try await svc.currentOpId(repoPath: "/repo")
        #expect(op == "abc1234")
    }
}
```

Note: `version()` no longer takes `repoPath:` because `--version` is a global flag (Minor #8 from review). The implementation in Step 3 will reflect this.

- [ ] **Step 2: Run to verify tests fail**

Run: `swift test --filter JjRepositoryServiceTests`
Expected: compile error — labels don't match yet, `version()` arity wrong.

- [ ] **Step 3: Move typealias to runner + rewrite service**

Edit `Muxy/Services/Jj/JjProcessRunner.swift`. After the closing brace of the existing `extension JjProcessRunner { ... }` block (Task 3 of foundation), append:

```swift
typealias JjRunFn = @Sendable (
    _ repoPath: String,
    _ command: [String],
    _ snapshot: JjSnapshotPolicy,
    _ atOp: String?
) async throws -> JjProcessResult
```

(Internal-only — Task 3 of this plan narrows visibility.)

Then replace `Muxy/Services/Jj/JjRepositoryService.swift` contents:

```swift
import Foundation
import MuxyShared

struct JjRepositoryService: Sendable {
    private let runner: JjRunFn

    init(runner: @escaping JjRunFn = { repoPath, command, snapshot, atOp in
        try await JjProcessRunner.run(
            repoPath: repoPath,
            command: command,
            snapshot: snapshot,
            atOp: atOp
        )
    }) {
        self.runner = runner
    }

    func isJjRepo(repoPath: String) async throws -> Bool {
        let result = try await runner(repoPath, ["root"], .ignore, nil)
        return result.status == 0
    }

    func version() async throws -> JjVersion {
        guard let exec = JjProcessRunner.resolveExecutable() else {
            throw JjProcessError.launchFailed("jj not found on PATH")
        }
        let result = try await JjProcessRunner.runRaw(executable: exec, arguments: ["--version"])
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjVersion.parse(raw)
    }

    func currentOpId(repoPath: String) async throws -> String {
        let result = try await runner(
            repoPath,
            ["op", "log", "-n", "1", "--no-graph", "-T", JjOpLogParser.template],
            .ignore,
            nil
        )
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        let ops = try JjOpLogParser.parse(raw)
        guard let first = ops.first else {
            throw JjProcessError.nonZeroExit(status: 0, stderr: "empty op log")
        }
        return first.id
    }
}
```

- [ ] **Step 4: Add JjProcessRunner.runRaw bypass for repoPath-less commands**

In `Muxy/Services/Jj/JjProcessRunner.swift`, append to the existing `extension JjProcessRunner { ... }`:

```swift
static func runRaw(
    executable: String,
    arguments: [String]
) async throws -> JjProcessResult {
    let env = buildEnvironment(inherited: ProcessInfo.processInfo.environment)
    return try await Task.detached(priority: .userInitiated) {
        try runProcess(executable: executable, arguments: arguments, environment: env)
    }.value
}
```

(Reuses the existing private `runProcess` for `--version` etc. that don't take `--repository`.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter JjRepositoryServiceTests`
Expected: 4/4 pass.

Run: `swift test --filter Jj`
Expected: all (38+) Jj suite tests pass.

- [ ] **Step 6: Commit**

```bash
jj commit -m "refactor(jj): centralize JjRunFn in runner, normalize repoPath labels"
```

---

### Task 3: Narrow public → internal

**Files:**
- Modify: `Muxy/Services/Jj/JjProcessRunner.swift`
- Modify: `Muxy/Services/Jj/JjProcessQueue.swift`
- Modify: `Muxy/Services/Jj/JjVersion.swift`
- Modify: `Muxy/Services/Jj/JjStatusParser.swift`
- Modify: `Muxy/Services/Jj/JjOpLogParser.swift`
- Modify: `Muxy/Services/Jj/JjConflictParser.swift`
- Modify: `Muxy/Services/Jj/JjWorkspaceParser.swift`
- Modify: `Muxy/Services/Jj/JjRepositoryService.swift`
- Modify: `Muxy/Services/Jj/JjWorkspaceService.swift`

DTOs in `MuxyShared/Jj/JjModels.swift` stay public (cross-target boundary). Everything in `Muxy/Services/Jj/` is internal — the Roost target uses these directly, tests reach them via `@testable import Roost`.

- [ ] **Step 1: Bulk strip `public` keyword from each Service-layer file**

For each file in `Muxy/Services/Jj/*.swift`, remove `public` keyword from:
- enum/struct/actor declarations
- typealiases
- static let / static func / func declarations
- init declarations
- enum cases (these were already not public-marked, but verify)

Do NOT touch `MuxyShared/Jj/JjModels.swift`. Do NOT touch the existing extension on `JjVersion` in `JjVersion.swift` — `extension JjVersion` (no `public`) gives internal members; the previous `public extension JjVersion` becomes `extension JjVersion`.

Concrete: open each file and run a single-pass replace of `public ` (with trailing space) with empty string only in `Muxy/Services/Jj/`.

- [ ] **Step 2: Run all Jj tests**

Run: `swift test --filter Jj`
Expected: still all pass (compile + runtime). Tests use `@testable import Roost` so internal symbols resolve.

If any test fails to compile because it expected `public`, that is a sign the symbol was leaking to non-testable consumers; review and either keep public (with justification) or fix the test.

- [ ] **Step 3: Run swift build**

Run: `swift build`
Expected: clean build. The Roost executable target uses these files directly so internal works.

- [ ] **Step 4: Commit**

```bash
jj commit -m "refactor(jj): narrow service-layer visibility to internal"
```

---

### Task 4: JjBookmarkParser

**Files:**
- Create: `Muxy/Services/Jj/JjBookmarkParser.swift`
- Test: `Tests/MuxyTests/Jj/JjBookmarkParserTests.swift`

`jj bookmark list --color=never -T 'self.name() ++ "\t" ++ if(self.normal_target(), self.normal_target().change_id().shortest(), "(no target)") ++ "\t" ++ if(self.normal_target(), self.normal_target().change_id(), "") ++ "\t" ++ self.remote_targets().map(|t| t.remote()).join(",") ++ "\n"'`

That gives lines:
```
main	vk[rwwqlnruos]	vkrwwqlnruosabcdef0123	origin,muxy-upstream
feat-x	t[oxztuvoploo]	toxztuvoplooabcdef4567	
```

Format: name TAB short-prefix-bracketed-id TAB full-id TAB comma-remotes.
Empty remotes column means local-only.

- [ ] **Step 1: Write the failing tests**

Create `Tests/MuxyTests/Jj/JjBookmarkParserTests.swift`:

```swift
import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjBookmarkParser")
struct JjBookmarkParserTests {
    @Test("parses single local bookmark")
    func singleLocal() throws {
        let raw = "main\tvk[rwwqlnruos]\tvkrwwqlnruosabcdef\t\n"
        let bookmarks = try JjBookmarkParser.parse(raw)
        #expect(bookmarks.count == 1)
        #expect(bookmarks[0].name == "main")
        #expect(bookmarks[0].target?.prefix == "vk")
        #expect(bookmarks[0].target?.full == "vkrwwqlnruosabcdef")
        #expect(bookmarks[0].isLocal == true)
        #expect(bookmarks[0].remotes.isEmpty)
    }

    @Test("parses bookmark with remotes")
    func withRemotes() throws {
        let raw = "main\tvk[rwwqlnruos]\tvkrwwqlnruosabcdef\torigin,muxy-upstream\n"
        let bookmarks = try JjBookmarkParser.parse(raw)
        #expect(bookmarks[0].remotes == ["origin", "muxy-upstream"])
        #expect(bookmarks[0].isLocal == false)
    }

    @Test("parses no-target bookmark")
    func noTarget() throws {
        let raw = "deleted\t(no target)\t\t\n"
        let bookmarks = try JjBookmarkParser.parse(raw)
        #expect(bookmarks[0].name == "deleted")
        #expect(bookmarks[0].target == nil)
    }

    @Test("rejects malformed line")
    func malformed() {
        #expect(throws: (any Error).self) {
            _ = try JjBookmarkParser.parse("only one column\n")
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter JjBookmarkParserTests`
Expected: compile error — `JjBookmarkParser` undefined.

- [ ] **Step 3: Implement parser**

Create `Muxy/Services/Jj/JjBookmarkParser.swift`:

```swift
import Foundation
import MuxyShared

enum JjBookmarkParseError: Error, Sendable {
    case malformedLine(String)
}

enum JjBookmarkParser {
    static let template = #"self.name() ++ "\t" ++ if(self.normal_target(), self.normal_target().change_id().shortest(), "(no target)") ++ "\t" ++ if(self.normal_target(), self.normal_target().change_id(), "") ++ "\t" ++ self.remote_targets().map(|t| t.remote()).join(",") ++ "\n""#

    static func parse(_ raw: String) throws -> [JjBookmark] {
        var bookmarks: [JjBookmark] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4 else {
                throw JjBookmarkParseError.malformedLine(String(line))
            }
            let name = String(parts[0])
            let shortToken = String(parts[1])
            let fullToken = String(parts[2])
            let remotesRaw = String(parts[3])

            let target: JjChangeId? = if shortToken == "(no target)" {
                nil
            } else {
                try parseShortAndFullChangeId(shortToken: shortToken, full: fullToken)
            }

            let remotes = remotesRaw.isEmpty
                ? []
                : remotesRaw.split(separator: ",").map(String.init)

            bookmarks.append(JjBookmark(
                name: name,
                target: target,
                isLocal: remotes.isEmpty,
                remotes: remotes
            ))
        }
        return bookmarks
    }

    private static func parseShortAndFullChangeId(shortToken: String, full: String) throws -> JjChangeId {
        guard let openBracket = shortToken.firstIndex(of: "[") else {
            return JjChangeId(prefix: shortToken, full: full.isEmpty ? shortToken : full)
        }
        guard shortToken.last == "]" else {
            throw JjBookmarkParseError.malformedLine(shortToken)
        }
        let prefix = String(shortToken[..<openBracket])
        let resolvedFull = full.isEmpty ? prefix + String(shortToken[shortToken.index(after: openBracket)..<shortToken.index(before: shortToken.endIndex)]) : full
        return JjChangeId(prefix: prefix, full: resolvedFull)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter JjBookmarkParserTests`
Expected: 4/4 pass.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): JjBookmarkParser with template constant"
```

---

### Task 5: JjBookmarkService

**Files:**
- Create: `Muxy/Services/Jj/JjBookmarkService.swift`
- Test: `Tests/MuxyTests/Jj/JjBookmarkServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MuxyTests/Jj/JjBookmarkServiceTests.swift`:

```swift
import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjBookmarkService")
struct JjBookmarkServiceTests {
    @Test("list parses bookmarks")
    func list() async throws {
        let svc = JjBookmarkService(queue: JjProcessQueue()) { _, _, _, _ in
            JjProcessResult(
                status: 0,
                stdout: Data("main\tvk[rwwqlnruos]\tvkrwwqlnruosabcdef\torigin\n".utf8),
                stderr: ""
            )
        }
        let bookmarks = try await svc.list(repoPath: "/repo")
        #expect(bookmarks.count == 1)
        #expect(bookmarks[0].name == "main")
        #expect(bookmarks[0].remotes == ["origin"])
    }

    @Test("create invokes bookmark create")
    func create() async throws {
        let captured = CapturedCall()
        let svc = JjBookmarkService(queue: JjProcessQueue()) { repo, cmd, snapshot, _ in
            await captured.set(repo: repo, cmd: cmd, snapshot: snapshot)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        try await svc.create(repoPath: "/repo", name: "feat-x", revset: nil)
        let cmd = await captured.cmd
        let snapshot = await captured.snapshot
        #expect(cmd == ["bookmark", "create", "feat-x"])
        #expect(snapshot == .allow)
    }

    @Test("create with revset adds -r")
    func createWithRevset() async throws {
        let captured = CapturedCall()
        let svc = JjBookmarkService(queue: JjProcessQueue()) { repo, cmd, _, _ in
            await captured.set(repo: repo, cmd: cmd, snapshot: .allow)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        try await svc.create(repoPath: "/repo", name: "feat-x", revset: "@-")
        let cmd = await captured.cmd
        #expect(cmd == ["bookmark", "create", "feat-x", "-r", "@-"])
    }

    @Test("set moves existing bookmark")
    func set() async throws {
        let captured = CapturedCall()
        let svc = JjBookmarkService(queue: JjProcessQueue()) { repo, cmd, _, _ in
            await captured.set(repo: repo, cmd: cmd, snapshot: .allow)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        try await svc.setTarget(repoPath: "/repo", name: "main", revset: "@-")
        let cmd = await captured.cmd
        #expect(cmd == ["bookmark", "set", "main", "-r", "@-"])
    }

    @Test("forget deletes bookmark")
    func forget() async throws {
        let captured = CapturedCall()
        let svc = JjBookmarkService(queue: JjProcessQueue()) { repo, cmd, _, _ in
            await captured.set(repo: repo, cmd: cmd, snapshot: .allow)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        try await svc.forget(repoPath: "/repo", name: "feat-x")
        let cmd = await captured.cmd
        #expect(cmd == ["bookmark", "forget", "feat-x"])
    }
}

actor CapturedCall {
    var repo: String = ""
    var cmd: [String] = []
    var snapshot: JjSnapshotPolicy = .ignore
    func set(repo: String, cmd: [String], snapshot: JjSnapshotPolicy) {
        self.repo = repo
        self.cmd = cmd
        self.snapshot = snapshot
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter JjBookmarkServiceTests`
Expected: compile error.

- [ ] **Step 3: Implement service**

Create `Muxy/Services/Jj/JjBookmarkService.swift`:

```swift
import Foundation
import MuxyShared

struct JjBookmarkService: Sendable {
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

    func list(repoPath: String) async throws -> [JjBookmark] {
        let result = try await runner(
            repoPath,
            ["bookmark", "list", "--no-graph", "-T", JjBookmarkParser.template],
            .ignore,
            nil
        )
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjBookmarkParser.parse(raw)
    }

    func create(repoPath: String, name: String, revset: String?) async throws {
        var cmd: [String] = ["bookmark", "create", name]
        if let revset {
            cmd += ["-r", revset]
        }
        try await runMutating(repoPath: repoPath, command: cmd)
    }

    func setTarget(repoPath: String, name: String, revset: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["bookmark", "set", name, "-r", revset])
    }

    func forget(repoPath: String, name: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["bookmark", "forget", name])
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter JjBookmarkServiceTests`
Expected: 5/5 pass.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): JjBookmarkService with create/set/forget mutations"
```

---

### Task 6: JjDiffParser

**Files:**
- Modify: `MuxyShared/Jj/JjModels.swift` (add JjDiffStat + JjDiffFileStat)
- Create: `Muxy/Services/Jj/JjDiffParser.swift`
- Test: `Tests/MuxyTests/Jj/JjDiffParserTests.swift`

`jj diff --stat --color=never` output:
```
docs/new.md         | 12 ++++++++++++
Muxy/Foo.swift      |  4 ++--
Muxy/Bar.swift      |  3 ---
3 files changed, 17 insertions(+), 5 deletions(-)
```

`jj diff --summary --color=never`:
```
A docs/new.md
M Muxy/Foo.swift
D Muxy/Bar.swift
```

This task only handles `--stat` (the more useful + more parseable format). `--summary` parsing is identical to `JjStatusParser.parseChangeLine` — we'll reuse that in the service in Task 7.

- [ ] **Step 1: Add DTOs to MuxyShared**

Append to `MuxyShared/Jj/JjModels.swift`:

```swift
public struct JjDiffFileStat: Hashable, Sendable, Codable {
    public let path: String
    public let additions: Int
    public let deletions: Int

    public init(path: String, additions: Int, deletions: Int) {
        self.path = path
        self.additions = additions
        self.deletions = deletions
    }
}

public struct JjDiffStat: Sendable, Codable {
    public let files: [JjDiffFileStat]
    public let totalAdditions: Int
    public let totalDeletions: Int

    public init(files: [JjDiffFileStat], totalAdditions: Int, totalDeletions: Int) {
        self.files = files
        self.totalAdditions = totalAdditions
        self.totalDeletions = totalDeletions
    }
}
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/MuxyTests/Jj/JjDiffParserTests.swift`:

```swift
import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjDiffParser")
struct JjDiffParserTests {
    @Test("parses --stat output")
    func parsesStat() throws {
        let raw = """
        docs/new.md         | 12 ++++++++++++
        Muxy/Foo.swift      |  4 ++--
        Muxy/Bar.swift      |  3 ---
        3 files changed, 17 insertions(+), 5 deletions(-)
        """
        let stat = try JjDiffParser.parseStat(raw)
        #expect(stat.files.count == 3)
        #expect(stat.files[0] == JjDiffFileStat(path: "docs/new.md", additions: 12, deletions: 0))
        #expect(stat.files[1] == JjDiffFileStat(path: "Muxy/Foo.swift", additions: 2, deletions: 2))
        #expect(stat.files[2] == JjDiffFileStat(path: "Muxy/Bar.swift", additions: 0, deletions: 3))
        #expect(stat.totalAdditions == 17)
        #expect(stat.totalDeletions == 5)
    }

    @Test("path with spaces in --stat")
    func pathWithSpaces() throws {
        let raw = """
        sub/file with spaces.txt   | 4 ++--
        1 file changed, 2 insertions(+), 2 deletions(-)
        """
        let stat = try JjDiffParser.parseStat(raw)
        #expect(stat.files.count == 1)
        #expect(stat.files[0].path == "sub/file with spaces.txt")
        #expect(stat.files[0].additions == 2)
        #expect(stat.files[0].deletions == 2)
    }

    @Test("empty diff")
    func empty() throws {
        let stat = try JjDiffParser.parseStat("")
        #expect(stat.files.isEmpty)
        #expect(stat.totalAdditions == 0)
        #expect(stat.totalDeletions == 0)
    }

    @Test("rejects malformed file line")
    func malformedFileLine() {
        let raw = "garbage no separator\n"
        #expect(throws: (any Error).self) {
            _ = try JjDiffParser.parseStat(raw)
        }
    }
}
```

- [ ] **Step 3: Run tests to verify failure**

Run: `swift test --filter JjDiffParserTests`
Expected: compile error.

- [ ] **Step 4: Implement parser**

Create `Muxy/Services/Jj/JjDiffParser.swift`:

```swift
import Foundation
import MuxyShared

enum JjDiffParseError: Error, Sendable {
    case malformedFileLine(String)
}

enum JjDiffParser {
    static func parseStat(_ raw: String) throws -> JjDiffStat {
        var files: [JjDiffFileStat] = []
        var totalAdditions = 0
        var totalDeletions = 0

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line)
            if let summary = parseSummaryLine(s) {
                totalAdditions = summary.additions
                totalDeletions = summary.deletions
                continue
            }
            files.append(try parseFileLine(s))
        }
        return JjDiffStat(files: files, totalAdditions: totalAdditions, totalDeletions: totalDeletions)
    }

    private static func parseFileLine(_ s: String) throws -> JjDiffFileStat {
        guard let pipe = s.firstIndex(of: "|") else {
            throw JjDiffParseError.malformedFileLine(s)
        }
        let path = String(s[..<pipe]).trimmingCharacters(in: .whitespaces)
        let counts = String(s[s.index(after: pipe)...]).trimmingCharacters(in: .whitespaces)
        let parts = counts.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw JjDiffParseError.malformedFileLine(s)
        }
        let symbols = String(parts[1])
        let additions = symbols.filter { $0 == "+" }.count
        let deletions = symbols.filter { $0 == "-" }.count
        return JjDiffFileStat(path: path, additions: additions, deletions: deletions)
    }

    private struct Summary {
        let additions: Int
        let deletions: Int
    }

    private static func parseSummaryLine(_ s: String) -> Summary? {
        guard s.contains("file") && s.contains("changed") else { return nil }
        let additions = extract(numberBefore: "insertion", in: s) ?? 0
        let deletions = extract(numberBefore: "deletion", in: s) ?? 0
        return Summary(additions: additions, deletions: deletions)
    }

    private static func extract(numberBefore keyword: String, in s: String) -> Int? {
        guard let range = s.range(of: keyword) else { return nil }
        let before = s[..<range.lowerBound]
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        let lastToken = trimmed.split(separator: " ").last.map(String.init) ?? ""
        return Int(lastToken)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter JjDiffParserTests`
Expected: 4/4 pass.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(jj): JjDiffParser for --stat output + JjDiffStat DTOs"
```

---

### Task 7: JjDiffService

**Files:**
- Create: `Muxy/Services/Jj/JjDiffService.swift`
- Test: `Tests/MuxyTests/Jj/JjDiffServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MuxyTests/Jj/JjDiffServiceTests.swift`:

```swift
import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjDiffService")
struct JjDiffServiceTests {
    @Test("stat parses --stat output")
    func stat() async throws {
        let svc = JjDiffService { _, _, _, _ in
            JjProcessResult(
                status: 0,
                stdout: Data("docs/new.md | 4 ++--\n1 file changed, 2 insertions(+), 2 deletions(-)\n".utf8),
                stderr: ""
            )
        }
        let stat = try await svc.stat(repoPath: "/repo", revset: "@")
        #expect(stat.files.count == 1)
        #expect(stat.files[0].path == "docs/new.md")
        #expect(stat.totalAdditions == 2)
    }

    @Test("summary uses --summary and reuses status entry parser")
    func summary() async throws {
        let svc = JjDiffService { _, _, _, _ in
            JjProcessResult(
                status: 0,
                stdout: Data("A docs/new.md\nM Muxy/Foo.swift\n".utf8),
                stderr: ""
            )
        }
        let entries = try await svc.summary(repoPath: "/repo", revset: "@")
        #expect(entries.count == 2)
        #expect(entries[0] == JjStatusEntry(change: .added, path: "docs/new.md"))
        #expect(entries[1] == JjStatusEntry(change: .modified, path: "Muxy/Foo.swift"))
    }

    @Test("stat invokes correct command")
    func statCommand() async throws {
        let captured = CapturedCall()
        let svc = JjDiffService { repo, cmd, snapshot, _ in
            await captured.set(repo: repo, cmd: cmd, snapshot: snapshot)
            return JjProcessResult(status: 0, stdout: Data("0 files changed, 0 insertions(+), 0 deletions(-)\n".utf8), stderr: "")
        }
        _ = try await svc.stat(repoPath: "/repo", revset: "@-")
        let cmd = await captured.cmd
        let snapshot = await captured.snapshot
        #expect(cmd == ["diff", "--stat", "-r", "@-"])
        #expect(snapshot == .ignore)
    }
}
```

(Reuses `actor CapturedCall` from `JjBookmarkServiceTests.swift`.)

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter JjDiffServiceTests`
Expected: compile error.

- [ ] **Step 3: Implement service**

Create `Muxy/Services/Jj/JjDiffService.swift`:

```swift
import Foundation
import MuxyShared

struct JjDiffService: Sendable {
    private let runner: JjRunFn

    init(runner: @escaping JjRunFn = { repoPath, command, snapshot, atOp in
        try await JjProcessRunner.run(
            repoPath: repoPath,
            command: command,
            snapshot: snapshot,
            atOp: atOp
        )
    }) {
        self.runner = runner
    }

    func stat(repoPath: String, revset: String) async throws -> JjDiffStat {
        let result = try await runner(repoPath, ["diff", "--stat", "-r", revset], .ignore, nil)
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjDiffParser.parseStat(raw)
    }

    func summary(repoPath: String, revset: String) async throws -> [JjStatusEntry] {
        let result = try await runner(repoPath, ["diff", "--summary", "-r", revset], .ignore, nil)
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjStatusParser.parseSummaryEntries(raw)
    }
}
```

- [ ] **Step 4: Expose JjStatusParser.parseSummaryEntries**

`JjDiffService.summary` reuses status-entry parsing. Add this static helper to `Muxy/Services/Jj/JjStatusParser.swift` (place it inside `enum JjStatusParser`, after `parse(_:)`):

```swift
static func parseSummaryEntries(_ raw: String) throws -> [JjStatusEntry] {
    var entries: [JjStatusEntry] = []
    for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
        if let entry = parseChangeLine(String(line)) {
            entries.append(entry)
        }
    }
    return entries
}
```

(`parseChangeLine` is already private static; keep it private — `parseSummaryEntries` is the public-facing API.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter JjDiffServiceTests`
Expected: 3/3 pass.

Run: `swift test --filter Jj`
Expected: full Jj suite passes.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(jj): JjDiffService with stat + summary modes"
```

---

### Task 8: JjRepositoryService.show

**Files:**
- Modify: `Muxy/Services/Jj/JjRepositoryService.swift`
- Modify: `MuxyShared/Jj/JjModels.swift` (add `JjShowOutput`)
- Modify: `Tests/MuxyTests/Jj/JjRepositoryServiceTests.swift`

`jj show -r <rev> --color=never -T '<change-template>' --no-pager` returns the change description; with `--stat` it appends a diff-stat block.

This task adds a thin `show(repoPath:revset:)` that returns a structured `JjShowOutput` parsed from a templated header + stat block.

- [ ] **Step 1: Add JjShowOutput DTO**

Append to `MuxyShared/Jj/JjModels.swift`:

```swift
public struct JjShowOutput: Sendable, Codable {
    public let change: JjChangeId
    public let parents: [JjChangeId]
    public let description: String
    public let diffStat: JjDiffStat?

    public init(change: JjChangeId, parents: [JjChangeId], description: String, diffStat: JjDiffStat?) {
        self.change = change
        self.parents = parents
        self.description = description
        self.diffStat = diffStat
    }
}
```

- [ ] **Step 2: Write the failing test**

Append to `Tests/MuxyTests/Jj/JjRepositoryServiceTests.swift` (inside the existing `@Suite`):

```swift
@Test("show returns parsed change + stat")
func show() async throws {
    let stub = """
    CHANGE\tt[oxztuvoploo]\ttoxztuvoploofullhash
    PARENTS\tz[zzzzzzzzzzz]\tzzzzzzzzzzzzfullhash
    DESCRIPTION
    feat: example
    body line
    END_DESCRIPTION
    docs/new.md | 4 ++--
    1 file changed, 2 insertions(+), 2 deletions(-)
    """
    let svc = JjRepositoryService { _, _, _, _ in
        JjProcessResult(status: 0, stdout: Data(stub.utf8), stderr: "")
    }
    let result = try await svc.show(repoPath: "/repo", revset: "@")
    #expect(result.change.full == "toxztuvoploofullhash")
    #expect(result.parents.first?.full == "zzzzzzzzzzzzfullhash")
    #expect(result.description == "feat: example\nbody line")
    #expect(result.diffStat?.files.count == 1)
    #expect(result.diffStat?.files[0].path == "docs/new.md")
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter JjRepositoryServiceTests`
Expected: compile error — `svc.show` doesn't exist.

- [ ] **Step 4: Implement show + parser**

Add to `Muxy/Services/Jj/JjRepositoryService.swift` (inside the struct):

```swift
func show(repoPath: String, revset: String) async throws -> JjShowOutput {
    let template = #""CHANGE\t" ++ self.change_id().shortest() ++ "\t" ++ self.change_id() ++ "\n" ++ self.parents().map(|p| "PARENTS\t" ++ p.change_id().shortest() ++ "\t" ++ p.change_id()).join("\n") ++ "\nDESCRIPTION\n" ++ self.description() ++ "END_DESCRIPTION\n""#
    let result = try await runner(
        repoPath,
        ["show", "-r", revset, "--no-graph", "-T", template, "--stat"],
        .ignore,
        nil
    )
    guard result.status == 0 else {
        throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
    }
    let raw = String(data: result.stdout, encoding: .utf8) ?? ""
    return try JjShowParser.parse(raw)
}
```

Create `Muxy/Services/Jj/JjShowParser.swift`:

```swift
import Foundation
import MuxyShared

enum JjShowParseError: Error, Sendable {
    case missingChange
    case malformed(String)
}

enum JjShowParser {
    static func parse(_ raw: String) throws -> JjShowOutput {
        var change: JjChangeId?
        var parents: [JjChangeId] = []
        var descriptionLines: [String] = []
        var statLines: [String] = []
        var section: Section = .header

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            switch section {
            case .header:
                if line.hasPrefix("CHANGE\t") {
                    change = try parseTaggedId(line, expectedTag: "CHANGE")
                } else if line.hasPrefix("PARENTS\t") {
                    parents.append(try parseTaggedId(line, expectedTag: "PARENTS"))
                } else if line == "DESCRIPTION" {
                    section = .description
                }
            case .description:
                if line == "END_DESCRIPTION" {
                    section = .stat
                } else {
                    descriptionLines.append(line)
                }
            case .stat:
                if !line.isEmpty { statLines.append(line) }
            }
        }

        guard let change else { throw JjShowParseError.missingChange }
        let description = descriptionLines.joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        let diffStat = statLines.isEmpty ? nil : try JjDiffParser.parseStat(statLines.joined(separator: "\n"))
        return JjShowOutput(change: change, parents: parents, description: description, diffStat: diffStat)
    }

    private static func parseTaggedId(_ line: String, expectedTag: String) throws -> JjChangeId {
        let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == expectedTag else {
            throw JjShowParseError.malformed(line)
        }
        let shortToken = String(parts[1])
        let fullToken = String(parts[2])
        if let openBracket = shortToken.firstIndex(of: "[") {
            guard shortToken.last == "]" else {
                throw JjShowParseError.malformed(line)
            }
            let prefix = String(shortToken[..<openBracket])
            return JjChangeId(prefix: prefix, full: fullToken.isEmpty ? prefix : fullToken)
        }
        return JjChangeId(prefix: shortToken, full: fullToken.isEmpty ? shortToken : fullToken)
    }

    private enum Section {
        case header
        case description
        case stat
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter JjRepositoryServiceTests`
Expected: 5/5 pass (4 original + 1 show).

Run: `swift test --filter Jj`
Expected: full Jj suite passes.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(jj): JjRepositoryService.show + JjShowParser"
```

---

### Task 9: Plan note + final checks

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Run full check**

Run: `scripts/checks.sh --fix` (warns if formatters not installed; OK locally)
Run: `swift test --filter Jj`
Expected: all jj suites green (~50+ tests across ~14 suites).
Run: `swift build`
Expected: clean.

- [ ] **Step 2: Update Phase 1 status note**

Edit the "Foundation status" block in `docs/roost-migration-plan.md` Phase 1. Replace the bullet about outstanding Phase 1 items:

```markdown
- Outstanding Phase 1 items not in foundation: bookmark service (`bookmark create/list/forget/set`), `jj show`, diff service (`jj diff --stat` / `--summary`).
```

with:

```markdown
- Phase 1 services landed (2026-04-27): JjBookmarkParser/Service, JjDiffParser/Service (`--stat` + `--summary`), JjRepositoryService.show, JjShowParser. Refactor pass: JjProcessQueue is throwing-generic, JjRunFn lives in JjProcessRunner.swift, all service-layer types narrowed to internal. Plan: `docs/superpowers/plans/2026-04-27-jj-cleanup-and-bookmark-diff-services.md`.
- Outstanding before Phase 2 worktree adapter: data-migration plan for projects.json, Worktree field-mapping decisions (see Phase 2 spec).
```

- [ ] **Step 3: Commit**

```bash
jj commit -m "docs(jj): note Phase 1 services + cleanup landed"
```

---

## Self-Review

**Spec coverage** vs reviewer Important + Phase 1 remaining:

| Item | Covered by |
|------|-----------|
| Reviewer #3 throwing JjProcessQueue | Task 1 |
| Reviewer #4 path:↔repoPath: normalization | Task 2 |
| Reviewer #5 JjRunFn relocation | Task 2 |
| Reviewer #6 public→internal narrowing | Task 3 |
| Reviewer #8 jj --version no --repository | Task 2 (Step 4 runRaw) |
| Phase 1: bookmark service | Tasks 4–5 |
| Phase 1: diff service | Tasks 6–7 |
| Phase 1: jj show | Task 8 |

**Items deferred again** (acceptable):
- Reviewer #7 `JjChangeId.prefix == full` invariant — bookmark + show parsers in this plan now genuinely produce `prefix != full` in the bracketed case, so the invariant is broken in practice. The struct shape (separate `prefix`, `full`) is correct; no change needed.
- Reviewer #9 git binary hidden dependency — integration test only; deferred to a documentation task.
- Reviewer #10 `JjStatus.description` field naming — bigger refactor, out of scope.

**Placeholder scan:** No TODOs; every step has full code or exact command.

**Type consistency:** `JjRunFn` defined once in `JjProcessRunner.swift` (Task 2). All services use `repoPath:` (Tasks 2/5/7/8). `JjBookmark`/`JjDiffStat`/`JjDiffFileStat`/`JjShowOutput` defined once in `MuxyShared/Jj/JjModels.swift`. Parser names follow existing convention (`Jj<Domain>Parser` enum namespace).

---

## Abort criteria

If Task 8's `jj show` template doesn't yield parseable output on the user's local jj 0.40 (e.g., shortest-change-id formatting differs), **stop**: drop the show feature from this plan and ship through Task 7 only. The bookmark and diff services are independent and don't depend on show.
