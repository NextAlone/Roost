# jj Service Layer Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the jj subprocess + parser foundation that every later Roost phase (Worktree adapter, Sidebar, Changes panel) depends on, with the snapshot-isolation, environment-hygiene, and concurrency contracts locked from day one.

**Architecture:** A thin `JjProcessRunner` namespace owns environment hygiene + flag injection. A `JjProcessQueue` actor serializes mutating operations per repo path while letting reads run concurrently. Read-only commands default to `--ignore-working-copy` so UI polling never triggers a working-copy snapshot. Parsers consume jj's templated output (driven by `-T '<template>'` strings the runner controls) and are unit-tested with embedded string fixtures matching the existing `Tests/MuxyTests/Git/*ParserTests.swift` pattern. Service classes are thin shells over the runner with closure-based injection for unit testability.

**Tech Stack:** Swift 6 (strict concurrency), swift-testing, Foundation `Process`, jj ≥ 0.20.

**Out of scope (separate plans):** Worktree → JjWorkspace adapter (Phase 2), sidebar UI (Phase 4), Changes panel (Phase 5), hostd (Phase 6), `.roost/config.json` (Phase 7).

---

## File Structure

```
Muxy/Services/Jj/
  JjProcessRunner.swift     - subprocess launcher + env contract + flag injection
  JjProcessQueue.swift      - per-repo serialization actor
  JjVersion.swift           - parse `jj --version`, minimum-version check
  JjStatusParser.swift      - parse `jj status --color=never`
  JjOpLogParser.swift       - parse templated `jj op log` output
  JjConflictParser.swift    - parse `jj resolve --list`
  JjWorkspaceParser.swift   - parse `jj workspace list`
  JjRepositoryService.swift - root, version, currentOp, isJjRepo
  JjWorkspaceService.swift  - list, add, forget

MuxyShared/Jj/
  JjModels.swift            - DTOs (Sendable): JjChangeId, JjBookmark, JjOperation, JjStatusEntry, JjConflict, JjWorkspaceEntry, JjVersion

Tests/MuxyTests/Jj/
  JjProcessRunnerEnvTests.swift   - env construction unit tests
  JjVersionTests.swift            - version parsing
  JjStatusParserTests.swift       - status parser
  JjOpLogParserTests.swift        - op log parser
  JjConflictParserTests.swift     - conflict parser
  JjWorkspaceParserTests.swift    - workspace parser
  JjRepositoryServiceTests.swift  - service shell with stub runner
  JjWorkspaceServiceTests.swift   - service shell with stub runner
  JjIntegrationTests.swift        - live-jj smoke tests, gated on jj availability
```

Each file has one responsibility. Parsers are pure functions over `Data`/`String`. Services are thin shells that compose runner calls; injectable via closure for tests.

---

## Conventions for Every Task

- Branch: do all work on a single jj change off `main`. Each Step 5 commit advances `@`. Use `jj commit -m "<msg>"`.
- Test framework: swift-testing (`@Suite`, `@Test`, `#expect`). Match `Tests/MuxyTests/Git/GitStatusParserTests.swift` style.
- Module import in tests: `@testable import Roost` (Package target name; existing tests still importing `Muxy` are pre-existing breakage out of scope).
- All new types are `Sendable` unless impossible.
- After each task's commit step, also run `scripts/checks.sh --fix` and amend if it touches your files.

---

### Task 1: Sendable DTOs

**Files:**
- Create: `MuxyShared/Jj/JjModels.swift`

- [ ] **Step 1: Create the file with all DTOs**

```swift
import Foundation

public struct JjChangeId: Hashable, Sendable, Codable {
    public let prefix: String
    public let full: String

    public init(prefix: String, full: String) {
        self.prefix = prefix
        self.full = full
    }
}

public struct JjBookmark: Hashable, Sendable, Codable {
    public let name: String
    public let target: JjChangeId?
    public let isLocal: Bool
    public let remotes: [String]

    public init(name: String, target: JjChangeId?, isLocal: Bool, remotes: [String]) {
        self.name = name
        self.target = target
        self.isLocal = isLocal
        self.remotes = remotes
    }
}

public struct JjOperation: Hashable, Sendable, Codable {
    public let id: String
    public let timestamp: Date
    public let description: String

    public init(id: String, timestamp: Date, description: String) {
        self.id = id
        self.timestamp = timestamp
        self.description = description
    }
}

public enum JjFileChange: String, Sendable, Codable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
}

public struct JjStatusEntry: Hashable, Sendable, Codable {
    public let change: JjFileChange
    public let path: String
    public let oldPath: String?

    public init(change: JjFileChange, path: String, oldPath: String? = nil) {
        self.change = change
        self.path = path
        self.oldPath = oldPath
    }
}

public struct JjStatus: Sendable, Codable {
    public let workingCopy: JjChangeId
    public let parent: JjChangeId?
    public let description: String
    public let entries: [JjStatusEntry]
    public let hasConflicts: Bool

    public init(workingCopy: JjChangeId, parent: JjChangeId?, description: String, entries: [JjStatusEntry], hasConflicts: Bool) {
        self.workingCopy = workingCopy
        self.parent = parent
        self.description = description
        self.entries = entries
        self.hasConflicts = hasConflicts
    }
}

public struct JjConflict: Hashable, Sendable, Codable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct JjWorkspaceEntry: Hashable, Sendable, Codable {
    public let name: String
    public let workingCopy: JjChangeId

    public init(name: String, workingCopy: JjChangeId) {
        self.name = name
        self.workingCopy = workingCopy
    }
}

public struct JjVersion: Hashable, Sendable, Codable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: JjVersion, rhs: JjVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(jj): add Sendable DTOs for jj service layer"
```

---

### Task 2: JjProcessRunner — environment contract

**Files:**
- Create: `Muxy/Services/Jj/JjProcessRunner.swift`
- Test: `Tests/MuxyTests/Jj/JjProcessRunnerEnvTests.swift`

The runner's job in this task is **only** to construct the argument list and environment dictionary. The actual `Process` launch wraps that. We unit-test the construction in isolation.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("JjProcessRunner env + args")
struct JjProcessRunnerEnvTests {
    @Test("buildEnvironment strips JJ_* and sets locale")
    func envStripsAndSets() {
        let inherited = [
            "PATH": "/usr/local/bin:/usr/bin",
            "HOME": "/Users/test",
            "JJ_USER": "evil",
            "JJ_EMAIL": "evil@example.com",
            "JJ_CONFIG": "/keep/this",
            "LANG": "fr_FR.UTF-8",
            "TERM": "xterm-256color",
        ]
        let env = JjProcessRunner.buildEnvironment(inherited: inherited)
        #expect(env["LANG"] == "C.UTF-8")
        #expect(env["LC_ALL"] == "C.UTF-8")
        #expect(env["NO_COLOR"] == "1")
        #expect(env["JJ_USER"] == nil)
        #expect(env["JJ_EMAIL"] == nil)
        #expect(env["JJ_CONFIG"] == "/keep/this")
        #expect(env["HOME"] == "/Users/test")
        #expect(env["PATH"]?.contains("/usr/local/bin") == true)
    }

    @Test("buildArguments injects --no-pager --color=never for read commands")
    func argsInjectGlobals() {
        let args = JjProcessRunner.buildArguments(
            repoPath: "/repo",
            command: ["status"],
            snapshot: .ignore,
            atOp: nil
        )
        #expect(args.first == "--repository")
        #expect(args.contains("/repo"))
        #expect(args.contains("--no-pager"))
        #expect(args.contains("--color=never"))
        #expect(args.contains("--ignore-working-copy"))
        #expect(args.last == "status")
    }

    @Test("buildArguments injects --at-op when provided")
    func argsAtOp() {
        let args = JjProcessRunner.buildArguments(
            repoPath: "/repo",
            command: ["log", "-r", "@"],
            snapshot: .ignore,
            atOp: "abc123"
        )
        #expect(args.contains("--at-op"))
        #expect(args.contains("abc123"))
    }

    @Test("buildArguments omits --ignore-working-copy when snapshot is allowed")
    func argsAllowSnapshot() {
        let args = JjProcessRunner.buildArguments(
            repoPath: "/repo",
            command: ["new"],
            snapshot: .allow,
            atOp: nil
        )
        #expect(!args.contains("--ignore-working-copy"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter JjProcessRunnerEnvTests`
Expected: compile failure — `JjProcessRunner` not defined.

- [ ] **Step 3: Implement the runner**

```swift
import Foundation

public enum JjSnapshotPolicy: Sendable {
    case ignore
    case allow
}

public struct JjProcessResult: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: String
}

public enum JjProcessError: Error, Sendable {
    case launchFailed(String)
    case nonZeroExit(status: Int32, stderr: String)
}

public enum JjProcessRunner {
    public static let allowedInheritedKeys: Set<String> = [
        "HOME", "PATH", "USER", "LOGNAME", "TMPDIR", "JJ_CONFIG",
    ]

    public static func buildEnvironment(inherited: [String: String]) -> [String: String] {
        var env: [String: String] = [:]
        for (key, value) in inherited where allowedInheritedKeys.contains(key) {
            env[key] = value
        }
        env["LANG"] = "C.UTF-8"
        env["LC_ALL"] = "C.UTF-8"
        env["NO_COLOR"] = "1"
        if env["PATH"] == nil {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }
        return env
    }

    public static func buildArguments(
        repoPath: String,
        command: [String],
        snapshot: JjSnapshotPolicy,
        atOp: String?
    ) -> [String] {
        var args: [String] = ["--repository", repoPath, "--no-pager", "--color=never"]
        if snapshot == .ignore {
            args.append("--ignore-working-copy")
        }
        if let atOp {
            args.append(contentsOf: ["--at-op", atOp])
        }
        args.append(contentsOf: command)
        return args
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter JjProcessRunnerEnvTests`
Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): JjProcessRunner env + arg construction"
```

---

### Task 3: JjProcessRunner — actual subprocess launch

**Files:**
- Modify: `Muxy/Services/Jj/JjProcessRunner.swift`

This task wires `Process` around the env/args helpers. We don't unit-test the Process plumbing itself (it's covered by the integration smoke test in Task 11); we only verify the resolver helper.

- [ ] **Step 1: Add the resolver and run function**

Append to `Muxy/Services/Jj/JjProcessRunner.swift`:

```swift
extension JjProcessRunner {
    private static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ]

    public static func resolveExecutable() -> String? {
        for directory in searchPaths {
            let path = "\(directory)/jj"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    public static func run(
        repoPath: String,
        command: [String],
        snapshot: JjSnapshotPolicy,
        atOp: String? = nil
    ) async throws -> JjProcessResult {
        guard let exec = resolveExecutable() else {
            throw JjProcessError.launchFailed("jj not found on PATH")
        }
        let args = buildArguments(
            repoPath: repoPath,
            command: command,
            snapshot: snapshot,
            atOp: atOp
        )
        let env = buildEnvironment(inherited: ProcessInfo.processInfo.environment)
        return try await Task.detached(priority: .userInitiated) {
            try runProcess(executable: exec, arguments: args, environment: env)
        }.value
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> JjProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin
        try? stdin.fileHandleForWriting.close()

        do {
            try process.run()
        } catch {
            throw JjProcessError.launchFailed(String(describing: error))
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return JjProcessResult(
            status: process.terminationStatus,
            stdout: outData,
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(jj): JjProcessRunner subprocess launch with env hygiene"
```

---

### Task 4: JjProcessQueue — per-repo serialization actor

**Files:**
- Create: `Muxy/Services/Jj/JjProcessQueue.swift`
- Test: `Tests/MuxyTests/Jj/JjProcessQueueTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("JjProcessQueue")
struct JjProcessQueueTests {
    @Test("mutating operations on same repo are serialized")
    func serializesMutating() async {
        let queue = JjProcessQueue()
        let log = Log()
        async let a: Void = queue.run(repoPath: "/repo", isMutating: true) {
            await log.append("a-start")
            try? await Task.sleep(nanoseconds: 50_000_000)
            await log.append("a-end")
        }
        async let b: Void = queue.run(repoPath: "/repo", isMutating: true) {
            await log.append("b-start")
            await log.append("b-end")
        }
        _ = await (a, b)
        let entries = await log.entries
        #expect(entries == ["a-start", "a-end", "b-start", "b-end"]
            || entries == ["b-start", "b-end", "a-start", "a-end"])
    }

    @Test("read operations run concurrently")
    func readsConcurrent() async {
        let queue = JjProcessQueue()
        let log = Log()
        async let a: Void = queue.run(repoPath: "/repo", isMutating: false) {
            await log.append("a-start")
            try? await Task.sleep(nanoseconds: 50_000_000)
            await log.append("a-end")
        }
        async let b: Void = queue.run(repoPath: "/repo", isMutating: false) {
            await log.append("b-start")
            await log.append("b-end")
        }
        _ = await (a, b)
        let entries = await log.entries
        #expect(entries.firstIndex(of: "b-start")! < entries.firstIndex(of: "a-end")!)
    }
}

actor Log {
    var entries: [String] = []
    func append(_ s: String) { entries.append(s) }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter JjProcessQueueTests`
Expected: compile failure — `JjProcessQueue` not defined.

- [ ] **Step 3: Implement the actor**

```swift
import Foundation

public actor JjProcessQueue {
    private var inflight: [String: Task<Void, Never>] = [:]

    public init() {}

    public func run(repoPath: String, isMutating: Bool, body: @Sendable @escaping () async -> Void) async {
        if !isMutating {
            await body()
            return
        }
        let previous = inflight[repoPath]
        let task = Task {
            await previous?.value
            await body()
        }
        inflight[repoPath] = task
        await task.value
        if inflight[repoPath] == task {
            inflight[repoPath] = nil
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter JjProcessQueueTests`
Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): JjProcessQueue per-repo serialization actor"
```

---

### Task 5: JjVersion parsing + minimum check

**Files:**
- Create: `Muxy/Services/Jj/JjVersion.swift`
- Test: `Tests/MuxyTests/Jj/JjVersionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("JjVersion parsing")
struct JjVersionTests {
    @Test("parses standard release line")
    func parsesRelease() throws {
        let v = try JjVersion.parse("jj 0.20.0\n")
        #expect(v == JjVersion(major: 0, minor: 20, patch: 0))
    }

    @Test("parses dev suffix")
    func parsesDev() throws {
        let v = try JjVersion.parse("jj 0.21.0-dev (abc1234)\n")
        #expect(v == JjVersion(major: 0, minor: 21, patch: 0))
    }

    @Test("rejects malformed input")
    func rejectsGarbage() {
        #expect(throws: (any Error).self) {
            _ = try JjVersion.parse("not a version")
        }
    }

    @Test("minimum check")
    func minimum() throws {
        #expect(JjVersion.minimumSupported == JjVersion(major: 0, minor: 20, patch: 0))
        #expect(try JjVersion.parse("jj 0.19.0\n") < JjVersion.minimumSupported)
        #expect(try JjVersion.parse("jj 0.20.0\n") >= JjVersion.minimumSupported)
        #expect(try JjVersion.parse("jj 1.0.0\n") >= JjVersion.minimumSupported)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter JjVersionTests`
Expected: compile failure — no `JjVersion.parse` or `minimumSupported`.

- [ ] **Step 3: Implement parsing**

```swift
import Foundation

public enum JjVersionParseError: Error, Sendable {
    case malformed(String)
}

public extension JjVersion {
    static let minimumSupported = JjVersion(major: 0, minor: 20, patch: 0)

    static func parse(_ raw: String) throws -> JjVersion {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "jj" else {
            throw JjVersionParseError.malformed(raw)
        }
        let versionToken = parts[1].split(separator: "-", maxSplits: 1).first ?? parts[1]
        let nums = versionToken.split(separator: ".")
        guard nums.count == 3,
              let major = Int(nums[0]),
              let minor = Int(nums[1]),
              let patch = Int(nums[2]) else {
            throw JjVersionParseError.malformed(raw)
        }
        return JjVersion(major: major, minor: minor, patch: patch)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter JjVersionTests`
Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): JjVersion parser and minimum-supported constant"
```

---

### Task 6: JjStatusParser

**Files:**
- Create: `Muxy/Services/Jj/JjStatusParser.swift`
- Test: `Tests/MuxyTests/Jj/JjStatusParserTests.swift`

`jj status --color=never --ignore-working-copy` produces text like:

```
The working copy is clean
Working copy : abcdef12 default@ (no description set)
Parent commit: 12345678 main | feat: foo
```

or with changes:

```
Working copy changes:
A docs/new.md
M Muxy/Foo.swift
D Muxy/Bar.swift
R Muxy/Old.swift -> Muxy/New.swift
Working copy : abcdef12 default@ (no description set)
Parent commit: 12345678 main | feat: foo
There are unresolved conflicts at these paths:
Muxy/Conflict.swift
```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("JjStatusParser")
struct JjStatusParserTests {
    @Test("clean working copy")
    func clean() throws {
        let raw = """
        The working copy is clean
        Working copy : abcdef12 default@ (no description set)
        Parent commit: 12345678 main | feat: foo
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.entries.isEmpty)
        #expect(status.workingCopy.prefix == "abcdef12")
        #expect(status.parent?.prefix == "12345678")
        #expect(status.hasConflicts == false)
    }

    @Test("dirty with adds, mods, deletes")
    func dirty() throws {
        let raw = """
        Working copy changes:
        A docs/new.md
        M Muxy/Foo.swift
        D Muxy/Bar.swift
        Working copy : abcdef12 default@ (no description set)
        Parent commit: 12345678 main | feat: foo
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.entries.count == 3)
        #expect(status.entries[0] == JjStatusEntry(change: .added, path: "docs/new.md"))
        #expect(status.entries[1] == JjStatusEntry(change: .modified, path: "Muxy/Foo.swift"))
        #expect(status.entries[2] == JjStatusEntry(change: .deleted, path: "Muxy/Bar.swift"))
        #expect(status.hasConflicts == false)
    }

    @Test("rename keeps old path")
    func rename() throws {
        let raw = """
        Working copy changes:
        R Muxy/Old.swift -> Muxy/New.swift
        Working copy : abcdef12 default@ (no description set)
        Parent commit: 12345678 main | feat: foo
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.entries.count == 1)
        #expect(status.entries[0].change == .renamed)
        #expect(status.entries[0].path == "Muxy/New.swift")
        #expect(status.entries[0].oldPath == "Muxy/Old.swift")
    }

    @Test("conflicts surfaced")
    func conflicts() throws {
        let raw = """
        Working copy changes:
        M Muxy/Foo.swift
        Working copy : abcdef12 default@ (no description set)
        Parent commit: 12345678 main | feat: foo
        There are unresolved conflicts at these paths:
        Muxy/Foo.swift
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.hasConflicts == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter JjStatusParserTests`
Expected: compile failure — `JjStatusParser` not defined.

- [ ] **Step 3: Implement the parser**

```swift
import Foundation

public enum JjStatusParseError: Error, Sendable {
    case missingWorkingCopy
}

public enum JjStatusParser {
    public static func parse(_ raw: String) throws -> JjStatus {
        var entries: [JjStatusEntry] = []
        var workingCopy: JjChangeId?
        var parent: JjChangeId?
        var description = ""
        var hasConflicts = false
        var inConflictBlock = false

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("Working copy changes:") || s == "The working copy is clean" {
                inConflictBlock = false
                continue
            }
            if s.hasPrefix("There are unresolved conflicts") {
                hasConflicts = true
                inConflictBlock = true
                continue
            }
            if let prefix = s.prefixIfWorkingCopyLine() {
                workingCopy = prefix.changeId
                description = prefix.trailingDescription
                inConflictBlock = false
                continue
            }
            if let prefix = s.prefixIfParentLine() {
                parent = prefix.changeId
                inConflictBlock = false
                continue
            }
            if inConflictBlock {
                continue
            }
            if let entry = parseChangeLine(s) {
                entries.append(entry)
            }
        }

        guard let workingCopy else {
            throw JjStatusParseError.missingWorkingCopy
        }
        return JjStatus(
            workingCopy: workingCopy,
            parent: parent,
            description: description,
            entries: entries,
            hasConflicts: hasConflicts
        )
    }

    private static func parseChangeLine(_ s: String) -> JjStatusEntry? {
        guard s.count > 2, s[s.index(s.startIndex, offsetBy: 1)] == " " else { return nil }
        let code = String(s.first!)
        guard let change = JjFileChange(rawValue: code) else { return nil }
        let rest = String(s.dropFirst(2))
        if change == .renamed || change == .copied,
           let arrow = rest.range(of: " -> ") {
            return JjStatusEntry(
                change: change,
                path: String(rest[arrow.upperBound...]),
                oldPath: String(rest[..<arrow.lowerBound])
            )
        }
        return JjStatusEntry(change: change, path: rest)
    }
}

private struct ChangeLinePrefix {
    let changeId: JjChangeId
    let trailingDescription: String
}

private extension String {
    func prefixIfWorkingCopyLine() -> ChangeLinePrefix? {
        prefixIfMatchesLabel("Working copy : ")
    }

    func prefixIfParentLine() -> ChangeLinePrefix? {
        prefixIfMatchesLabel("Parent commit: ")
    }

    private func prefixIfMatchesLabel(_ label: String) -> ChangeLinePrefix? {
        guard hasPrefix(label) else { return nil }
        let rest = String(dropFirst(label.count))
        let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first else { return nil }
        let id = JjChangeId(prefix: String(first), full: String(first))
        let trailing = parts.count > 1 ? String(parts[1]) : ""
        return ChangeLinePrefix(changeId: id, trailingDescription: trailing)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter JjStatusParserTests`
Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): JjStatusParser with rename + conflict handling"
```

---

### Task 7: JjOpLogParser

**Files:**
- Create: `Muxy/Services/Jj/JjOpLogParser.swift`
- Test: `Tests/MuxyTests/Jj/JjOpLogParserTests.swift`

The runner will invoke op log with template:
`-T 'self.id().short() ++ "\t" ++ self.time().end().format("%Y-%m-%dT%H:%M:%S%:z") ++ "\t" ++ self.description() ++ "\n"'`

So lines look like:
```
abc1234	2026-04-27T10:15:30+00:00	commit
def5678	2026-04-27T10:14:00+00:00	new empty commit
```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("JjOpLogParser")
struct JjOpLogParserTests {
    @Test("parses single op")
    func single() throws {
        let raw = "abc1234\t2026-04-27T10:15:30+00:00\tcommit\n"
        let ops = try JjOpLogParser.parse(raw)
        #expect(ops.count == 1)
        #expect(ops[0].id == "abc1234")
        #expect(ops[0].description == "commit")
    }

    @Test("parses multiple ops in order")
    func multiple() throws {
        let raw = """
        abc1234\t2026-04-27T10:15:30+00:00\tcommit
        def5678\t2026-04-27T10:14:00+00:00\tnew empty commit

        """
        let ops = try JjOpLogParser.parse(raw)
        #expect(ops.count == 2)
        #expect(ops[0].id == "abc1234")
        #expect(ops[1].id == "def5678")
    }

    @Test("rejects malformed line")
    func malformed() {
        let raw = "abc1234 not a valid line\n"
        #expect(throws: (any Error).self) {
            _ = try JjOpLogParser.parse(raw)
        }
    }

    @Test("description may contain spaces")
    func descriptionSpaces() throws {
        let raw = "abc1234\t2026-04-27T10:15:30+00:00\tnew empty commit on top of @\n"
        let ops = try JjOpLogParser.parse(raw)
        #expect(ops[0].description == "new empty commit on top of @")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter JjOpLogParserTests`
Expected: compile failure — `JjOpLogParser` not defined.

- [ ] **Step 3: Implement the parser**

```swift
import Foundation

public enum JjOpLogParseError: Error, Sendable {
    case malformedLine(String)
}

public enum JjOpLogParser {
    public static let template = #"self.id().short() ++ "\t" ++ self.time().end().format("%Y-%m-%dT%H:%M:%S%:z") ++ "\t" ++ self.description() ++ "\n""#

    public static func parse(_ raw: String) throws -> [JjOperation] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        var ops: [JjOperation] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else {
                throw JjOpLogParseError.malformedLine(String(line))
            }
            guard let date = formatter.date(from: String(parts[1])) else {
                throw JjOpLogParseError.malformedLine(String(line))
            }
            ops.append(JjOperation(
                id: String(parts[0]),
                timestamp: date,
                description: String(parts[2])
            ))
        }
        return ops
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter JjOpLogParserTests`
Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): JjOpLogParser with template constant"
```

---

### Task 8: JjConflictParser + JjWorkspaceParser

**Files:**
- Create: `Muxy/Services/Jj/JjConflictParser.swift`
- Create: `Muxy/Services/Jj/JjWorkspaceParser.swift`
- Test: `Tests/MuxyTests/Jj/JjConflictParserTests.swift`
- Test: `Tests/MuxyTests/Jj/JjWorkspaceParserTests.swift`

`jj resolve --list --color=never` output:
```
Muxy/Foo.swift    2-sided conflict
Muxy/Bar.swift    2-sided conflict including 1 deletion
```

`jj workspace list --color=never` output:
```
default: abcdef12 (no description set)
my-feature: 12345678 feat: x
```

- [ ] **Step 1: Write conflict parser tests**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("JjConflictParser")
struct JjConflictParserTests {
    @Test("parses paths from resolve --list")
    func parsesPaths() {
        let raw = """
        Muxy/Foo.swift    2-sided conflict
        Muxy/Bar.swift    2-sided conflict including 1 deletion
        """
        let conflicts = JjConflictParser.parse(raw)
        #expect(conflicts.count == 2)
        #expect(conflicts[0].path == "Muxy/Foo.swift")
        #expect(conflicts[1].path == "Muxy/Bar.swift")
    }

    @Test("empty input")
    func empty() {
        #expect(JjConflictParser.parse("").isEmpty)
    }
}
```

- [ ] **Step 2: Write workspace parser tests**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("JjWorkspaceParser")
struct JjWorkspaceParserTests {
    @Test("parses two workspaces")
    func two() throws {
        let raw = """
        default: abcdef12 (no description set)
        my-feature: 12345678 feat: x
        """
        let entries = try JjWorkspaceParser.parse(raw)
        #expect(entries.count == 2)
        #expect(entries[0].name == "default")
        #expect(entries[0].workingCopy.prefix == "abcdef12")
        #expect(entries[1].name == "my-feature")
        #expect(entries[1].workingCopy.prefix == "12345678")
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter JjConflictParserTests`
Run: `swift test --filter JjWorkspaceParserTests`
Expected: compile failures — types not defined.

- [ ] **Step 4: Implement conflict parser**

```swift
import Foundation

public enum JjConflictParser {
    public static func parse(_ raw: String) -> [JjConflict] {
        raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let firstWS = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) {
                return JjConflict(path: String(trimmed[..<firstWS]))
            }
            return JjConflict(path: trimmed)
        }
    }
}
```

- [ ] **Step 5: Implement workspace parser**

```swift
import Foundation

public enum JjWorkspaceParseError: Error, Sendable {
    case malformedLine(String)
}

public enum JjWorkspaceParser {
    public static func parse(_ raw: String) throws -> [JjWorkspaceEntry] {
        var entries: [JjWorkspaceEntry] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line)
            guard let colon = s.firstIndex(of: ":") else {
                throw JjWorkspaceParseError.malformedLine(s)
            }
            let name = String(s[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = s[s.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let firstSpace = rest.firstIndex(of: " ") ?? rest.endIndex
            let id = String(rest[..<firstSpace])
            entries.append(JjWorkspaceEntry(
                name: name,
                workingCopy: JjChangeId(prefix: id, full: id)
            ))
        }
        return entries
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter JjConflictParserTests`
Run: `swift test --filter JjWorkspaceParserTests`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
jj commit -m "feat(jj): JjConflictParser + JjWorkspaceParser"
```

---

### Task 9: JjRepositoryService (with closure-injected runner for tests)

**Files:**
- Create: `Muxy/Services/Jj/JjRepositoryService.swift`
- Test: `Tests/MuxyTests/Jj/JjRepositoryServiceTests.swift`

Service injects a closure `(repoPath, command, snapshot, atOp) async throws -> JjProcessResult`. Production wires `JjProcessRunner.run`; tests stub it.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("JjRepositoryService")
struct JjRepositoryServiceTests {
    @Test("isJjRepo true on success")
    func isRepoTrue() async throws {
        let svc = JjRepositoryService { _, _, _, _ in
            JjProcessResult(status: 0, stdout: Data("/repo\n".utf8), stderr: "")
        }
        #expect(try await svc.isJjRepo(path: "/repo"))
    }

    @Test("isJjRepo false on non-zero exit")
    func isRepoFalse() async throws {
        let svc = JjRepositoryService { _, _, _, _ in
            JjProcessResult(status: 1, stdout: Data(), stderr: "no jj repo")
        }
        #expect(try await svc.isJjRepo(path: "/repo") == false)
    }

    @Test("version parses runner output")
    func version() async throws {
        let svc = JjRepositoryService { _, _, _, _ in
            JjProcessResult(status: 0, stdout: Data("jj 0.20.0\n".utf8), stderr: "")
        }
        let v = try await svc.version(path: "/repo")
        #expect(v == JjVersion(major: 0, minor: 20, patch: 0))
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
        let op = try await svc.currentOpId(path: "/repo")
        #expect(op == "abc1234")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter JjRepositoryServiceTests`
Expected: compile failure — `JjRepositoryService` not defined.

- [ ] **Step 3: Implement the service**

```swift
import Foundation

public typealias JjRunFn = @Sendable (
    _ repoPath: String,
    _ command: [String],
    _ snapshot: JjSnapshotPolicy,
    _ atOp: String?
) async throws -> JjProcessResult

public struct JjRepositoryService: Sendable {
    private let runner: JjRunFn

    public init(runner: @escaping JjRunFn = { repoPath, command, snapshot, atOp in
        try await JjProcessRunner.run(
            repoPath: repoPath,
            command: command,
            snapshot: snapshot,
            atOp: atOp
        )
    }) {
        self.runner = runner
    }

    public func isJjRepo(path: String) async throws -> Bool {
        let result = try await runner(path, ["root"], .ignore, nil)
        return result.status == 0
    }

    public func version(path: String) async throws -> JjVersion {
        let result = try await runner(path, ["--version"], .ignore, nil)
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjVersion.parse(raw)
    }

    public func currentOpId(path: String) async throws -> String {
        let result = try await runner(
            path,
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter JjRepositoryServiceTests`
Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): JjRepositoryService with closure-injected runner"
```

---

### Task 10: JjWorkspaceService (mutating ops route through queue)

**Files:**
- Create: `Muxy/Services/Jj/JjWorkspaceService.swift`
- Test: `Tests/MuxyTests/Jj/JjWorkspaceServiceTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("JjWorkspaceService")
struct JjWorkspaceServiceTests {
    @Test("list parses workspace entries")
    func list() async throws {
        let svc = JjWorkspaceService(queue: JjProcessQueue()) { _, _, _, _ in
            JjProcessResult(
                status: 0,
                stdout: Data("default: abcdef12 (no description set)\n".utf8),
                stderr: ""
            )
        }
        let entries = try await svc.list(repoPath: "/repo")
        #expect(entries.count == 1)
        #expect(entries[0].name == "default")
    }

    @Test("add invokes workspace add")
    func add() async throws {
        let captured = CapturedArgs()
        let svc = JjWorkspaceService(queue: JjProcessQueue()) { repo, cmd, _, _ in
            await captured.set(repo: repo, cmd: cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        try await svc.add(repoPath: "/repo", name: "feat-x", path: "/repo/.worktrees/feat-x")
        let cmd = await captured.cmd
        #expect(cmd == ["workspace", "add", "--name", "feat-x", "/repo/.worktrees/feat-x"])
    }

    @Test("forget invokes workspace forget")
    func forget() async throws {
        let captured = CapturedArgs()
        let svc = JjWorkspaceService(queue: JjProcessQueue()) { repo, cmd, _, _ in
            await captured.set(repo: repo, cmd: cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        try await svc.forget(repoPath: "/repo", name: "feat-x")
        let cmd = await captured.cmd
        #expect(cmd == ["workspace", "forget", "feat-x"])
    }
}

actor CapturedArgs {
    var repo: String = ""
    var cmd: [String] = []
    func set(repo: String, cmd: [String]) {
        self.repo = repo
        self.cmd = cmd
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter JjWorkspaceServiceTests`
Expected: compile failure — `JjWorkspaceService` not defined.

- [ ] **Step 3: Implement the service**

```swift
import Foundation

public struct JjWorkspaceService: Sendable {
    private let queue: JjProcessQueue
    private let runner: JjRunFn

    public init(queue: JjProcessQueue, runner: @escaping JjRunFn = { repoPath, command, snapshot, atOp in
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

    public func list(repoPath: String) async throws -> [JjWorkspaceEntry] {
        let result = try await runner(repoPath, ["workspace", "list"], .ignore, nil)
        guard result.status == 0 else {
            throw JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjWorkspaceParser.parse(raw)
    }

    public func add(repoPath: String, name: String, path: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["workspace", "add", "--name", name, path])
    }

    public func forget(repoPath: String, name: String) async throws {
        try await runMutating(repoPath: repoPath, command: ["workspace", "forget", name])
    }

    private func runMutating(repoPath: String, command: [String]) async throws {
        let runner = self.runner
        var thrown: Error?
        await queue.run(repoPath: repoPath, isMutating: true) {
            do {
                let result = try await runner(repoPath, command, .allow, nil)
                if result.status != 0 {
                    thrown = JjProcessError.nonZeroExit(status: result.status, stderr: result.stderr)
                }
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter JjWorkspaceServiceTests`
Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(jj): JjWorkspaceService routes mutating ops via queue"
```

---

### Task 11: Live-jj integration smoke test (gated)

**Files:**
- Create: `Tests/MuxyTests/Jj/JjIntegrationTests.swift`

Skipped at runtime if `jj` is not installed — so CI without jj still passes, but a developer with jj on PATH gets full validation.

- [ ] **Step 1: Write the integration test**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("Jj live integration", .enabled(if: JjProcessRunner.resolveExecutable() != nil))
struct JjIntegrationTests {
    @Test("create temp jj repo, query root + version + status + op")
    func smoke() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("jj-smoke-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let initResult = try await JjProcessRunner.run(
            repoPath: tmp.path,
            command: ["git", "init"],
            snapshot: .allow
        )
        #expect(initResult.status == 0, "jj git init failed: \(initResult.stderr)")

        let svc = JjRepositoryService()
        #expect(try await svc.isJjRepo(path: tmp.path))

        let v = try await svc.version(path: tmp.path)
        #expect(v >= JjVersion.minimumSupported, "jj version \(v) below minimum")

        let opId = try await svc.currentOpId(path: tmp.path)
        #expect(!opId.isEmpty)

        let statusResult = try await JjProcessRunner.run(
            repoPath: tmp.path,
            command: ["status"],
            snapshot: .ignore
        )
        let raw = String(data: statusResult.stdout, encoding: .utf8) ?? ""
        let status = try JjStatusParser.parse(raw)
        #expect(status.entries.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test**

Run: `swift test --filter JjIntegrationTests`
Expected: if `jj` is installed, smoke test passes. If `jj` is missing, test is skipped (suite condition false).

- [ ] **Step 3: Commit**

```bash
jj commit -m "test(jj): live integration smoke gated on jj availability"
```

---

### Task 12: Final pass — checks + plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Run the full check suite**

Run: `scripts/checks.sh --fix`
Expected: passes (or only `swiftformat`/`swiftlint` not installed warnings if local tooling missing). Re-run on a machine with the tools before merging.

- [ ] **Step 2: Run the full test suite**

Run: `swift test`
Expected: all jj suites pass. Existing test suites that import `Muxy` (legacy name) may still fail to compile — that is **out of scope** for this plan and tracked separately.

- [ ] **Step 3: Update the migration plan to mark Phase 1 foundation landed**

Edit `docs/roost-migration-plan.md` Phase 1 section, append at the end:

```markdown

Foundation landed on 2026-04-27 in `docs/superpowers/plans/2026-04-27-jj-service-layer-foundation.md`. Remaining Phase 1 items: bookmark service (`bookmark create/forget`), diff service, and Phase 2 worktree adapter integration.
```

- [ ] **Step 4: Commit**

```bash
jj commit -m "docs(jj): note Phase 1 service-layer foundation landed"
```

---

## Self-Review

**Spec coverage** (against the 🔴 + 🟡 items the foundation must cover):

| Audit item | Covered by |
|------------|-----------|
| 🔴 #1 snapshot race / `--ignore-working-copy` default | Task 2 (env+args), Task 9/10 use `.ignore` for reads |
| 🔴 #2 Swift 6 actor / async | Task 4 actor; all services `Sendable`; closure-injected runner |
| 🔴 #4 jj version pin / template-only output | Task 5 minimum version; Task 7 template constant; runner forces `--no-pager --color=never` |
| 🔴 #5 subprocess env contract | Task 2 `buildEnvironment` strips `JJ_*`, sets `LANG`/`NO_COLOR`/explicit `PATH`; Task 3 closes stdin |
| 🔴 #7 cross-process / 🟡 #14 mutating allowlist | Task 4 actor + Task 10 routes adds/forgets via queue with `.allow` snapshot |
| 🔴 #10 fixture-driven tests | Embedded-string fixtures in every parser test, matching existing Git pattern |
| 🔴 #11 `scripts/checks.sh` gate | Task 12 runs it explicitly |
| Phase 1 commands `op log`/`show`/`resolve`/`--at-op` | Task 7 (op log + template), Task 8 (resolve), Task 2/3 (`--at-op` parameter) |

Items deferred to follow-up plans (out of scope for this foundation):
- Bookmark service (`bookmark create/list/forget/set`)
- `jj show` wrapper
- Diff service (`jj diff --stat`/`--summary`)
- Phase 2 Worktree adapter (separate plan)

**Placeholder scan:** No TODOs, no "implement later", every code step has full code.

**Type consistency:** `JjRunFn`, `JjSnapshotPolicy`, `JjProcessResult`, `JjProcessError`, `JjChangeId`, `JjStatus`, `JjStatusEntry`, `JjFileChange`, `JjOperation`, `JjConflict`, `JjWorkspaceEntry`, `JjVersion` defined in Tasks 1–7 and used consistently in Tasks 9–11.

---

## Abort criteria

If after completing Tasks 1–7 (parsers + runner + version) the parser fixtures cannot be made to match real `jj 0.20+` output without per-version branching, **stop**: jj's textual output is too unstable to drive UI from. Pivot to a JSON-first approach (jj's experimental templater JSON output, when available) or prebuilt jj library bindings before continuing past Task 8.
