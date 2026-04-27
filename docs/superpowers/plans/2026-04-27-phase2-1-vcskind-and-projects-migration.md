# Phase 2.1 — VcsKind + projects.json schema migration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Land the data-layer foundation for Phase 2 worktree adapter without touching UI or command routing. Add `VcsKind` discriminator to `Worktree`, version `projects.json`, build the disk-probing VCS detector, and wire it into project add. Result: every `Worktree` carries an explicit `.git`/`.jj` tag, persistence round-trips through a versioned schema, and detector tests cover real on-disk repo shapes. No behavior changes (existing git flows continue identical because routing in 2.2 still defaults to git for `.git` repos).

**Architecture:** New `VcsKind` enum (Sendable, Codable, default `.git`). `Worktree` gains `vcsKind: VcsKind` + `currentChangeId: String?` with tolerant `decodeIfPresent` defaults. `ProjectsSchemaVersion` constant + reader/writer. `VcsKindDetector` probes `.jj` then `.git` on disk and falls back to `.git`. `ProjectOpenService` and `WorktreeStore` write detected kind onto new Worktree records. Migration is forward-only; Codable's `decodeIfPresent` makes v1 (no schemaVersion) load as v2 (vcsKind=.git defaulted).

**Tech Stack:** Swift 6, swift-testing, jj 0.20+ (already validated 0.40 in repo).

**Out of scope (Phase 2.2 plan):**
- Routing creation/removal calls to JjWorkspaceService for jj repos
- WorktreeStore.refreshFromGit conditional dispatch
- RemoteServerDelegate VCS controller protocol
- Sidebar jj workspace listing
- VCSTabState dual-service init
- WorktreeDTO mobile IPC update (deferred)

---

## File Structure

New:
```
Muxy/Models/VcsKind.swift
Muxy/Services/VcsKindDetector.swift
Tests/MuxyTests/Models/VcsKindTests.swift
Tests/MuxyTests/Services/VcsKindDetectorTests.swift
Tests/MuxyTests/Services/ProjectsMigrationTests.swift
```

Modified:
```
Muxy/Models/Worktree.swift          - add vcsKind + currentChangeId, tolerant decode
Muxy/Services/ProjectPersistence.swift - schemaVersion read/write
Muxy/Services/ProjectOpenService.swift - call detector on add
Muxy/Services/WorktreeStore.swift   - stamp vcsKind on new Worktree records
```

---

## Conventions

- Internal-by-default (no `public` keyword) — these symbols live in Roost target.
- Tests: swift-testing, `@testable import Roost` + `import MuxyShared` where needed.
- Project rule: no comments. jj-only VCS (use `jj commit -m`).
- After every commit: existing test suites continue to pass; specifically `swift test --filter Jj` and `swift test --filter Worktree` should remain green.

---

### Task 1: VcsKind enum

**Files:**
- Create: `Muxy/Models/VcsKind.swift`
- Test: `Tests/MuxyTests/Models/VcsKindTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("VcsKind")
struct VcsKindTests {
    @Test("default is git")
    func defaultGit() {
        #expect(VcsKind.default == .git)
    }

    @Test("Codable round-trips")
    func codable() throws {
        let original: [VcsKind] = [.git, .jj]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([VcsKind].self, from: data)
        #expect(decoded == original)
    }

    @Test("decodes from string raw value")
    func decodesFromString() throws {
        let json = "[\"git\", \"jj\"]"
        let decoded = try JSONDecoder().decode([VcsKind].self, from: Data(json.utf8))
        #expect(decoded == [.git, .jj])
    }

    @Test("unknown raw value throws")
    func unknownThrows() {
        let json = "[\"hg\"]"
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode([VcsKind].self, from: Data(json.utf8))
        }
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter VcsKindTests`
Expected: compile error — `VcsKind` undefined.

- [ ] **Step 3: Implement enum**

Create `Muxy/Models/VcsKind.swift`:

```swift
import Foundation

enum VcsKind: String, Sendable, Codable, Hashable, CaseIterable {
    case git
    case jj

    static let `default`: VcsKind = .git
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter VcsKindTests`
Expected: 4/4 pass.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(vcs): add VcsKind enum (.git default)"
```

---

### Task 2: Worktree gains vcsKind + currentChangeId with tolerant decode

**Files:**
- Modify: `Muxy/Models/Worktree.swift`
- Test: extend `Tests/MuxyTests/Models/VcsKindTests.swift` OR new file. Use new file for clarity:
  - Create: `Tests/MuxyTests/Models/WorktreeTolerantDecodeTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/MuxyTests/Models/WorktreeTolerantDecodeTests.swift`:

```swift
import Foundation
import Testing

@testable import Roost

@Suite("Worktree tolerant decode")
struct WorktreeTolerantDecodeTests {
    @Test("decodes v1 record (no vcsKind, no currentChangeId)")
    func v1Decode() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789012",
          "name": "main",
          "path": "/Users/me/repo",
          "branch": "main",
          "ownsBranch": false,
          "source": "muxy",
          "isPrimary": true,
          "createdAt": 776073600
        }
        """
        let decoded = try JSONDecoder.muxyDecoder.decode(Worktree.self, from: Data(json.utf8))
        #expect(decoded.vcsKind == .git)
        #expect(decoded.currentChangeId == nil)
        #expect(decoded.name == "main")
        #expect(decoded.branch == "main")
    }

    @Test("decodes v2 record with vcsKind and currentChangeId")
    func v2Decode() throws {
        let json = """
        {
          "id": "12345678-1234-1234-1234-123456789012",
          "name": "feat-x",
          "path": "/Users/me/repo/.worktrees/feat-x",
          "branch": "feat-x",
          "ownsBranch": true,
          "source": "muxy",
          "isPrimary": false,
          "createdAt": 776073600,
          "vcsKind": "jj",
          "currentChangeId": "vk[rwwqlnruos]"
        }
        """
        let decoded = try JSONDecoder.muxyDecoder.decode(Worktree.self, from: Data(json.utf8))
        #expect(decoded.vcsKind == .jj)
        #expect(decoded.currentChangeId == "vk[rwwqlnruos]")
    }

    @Test("encode v2 then decode round-trips")
    func roundTrip() throws {
        let original = Worktree(
            name: "feat",
            path: "/repo/.worktrees/feat",
            branch: "feat",
            ownsBranch: true,
            source: .muxy,
            isPrimary: false,
            vcsKind: .jj,
            currentChangeId: "abc123"
        )
        let data = try JSONEncoder.muxyEncoder.encode(original)
        let decoded = try JSONDecoder.muxyDecoder.decode(Worktree.self, from: data)
        #expect(decoded.vcsKind == .jj)
        #expect(decoded.currentChangeId == "abc123")
        #expect(decoded.branch == "feat")
    }
}
```

NOTE: assumes `JSONEncoder.muxyEncoder` / `JSONDecoder.muxyDecoder` exist as the project's standard encoders. If they don't, use plain `JSONEncoder()` / `JSONDecoder()` instead. Read `Muxy/Services/ProjectPersistence.swift` to confirm which form the project uses, and adapt the test accordingly. If neither exists, fall back to plain JSONEncoder/JSONDecoder — they handle Date as numeric seconds via `dateEncodingStrategy = .secondsSince1970` which we set explicitly. For the test, use plain `JSONEncoder()` / `JSONDecoder()` and set `.dateEncodingStrategy = .secondsSince1970` and `.dateDecodingStrategy = .secondsSince1970` inline.

The 776073600 value is `Date(timeIntervalSince1970: 776073600)` ≈ 1994-08-04 — use any deterministic value.

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter WorktreeTolerantDecodeTests`
Expected: compile error — Worktree init missing vcsKind/currentChangeId parameters; `vcsKind` field missing.

- [ ] **Step 3: Extend Worktree model**

Read current `Muxy/Models/Worktree.swift` first. Then update:

```swift
import Foundation

enum WorktreeSource: String, Codable, Hashable {
    case muxy
    case external
}

struct Worktree: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var branch: String?
    var ownsBranch: Bool
    var source: WorktreeSource
    var isPrimary: Bool
    var createdAt: Date
    var vcsKind: VcsKind
    var currentChangeId: String?

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        branch: String? = nil,
        ownsBranch: Bool = false,
        source: WorktreeSource = .muxy,
        isPrimary: Bool,
        createdAt: Date = Date(),
        vcsKind: VcsKind = .default,
        currentChangeId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.branch = branch
        self.ownsBranch = ownsBranch
        self.source = source
        self.isPrimary = isPrimary
        self.createdAt = createdAt
        self.vcsKind = vcsKind
        self.currentChangeId = currentChangeId
    }

    var isExternallyManaged: Bool {
        !isPrimary && source == .external
    }

    var canBeRemoved: Bool {
        !isPrimary && !isExternallyManaged
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case branch
        case ownsBranch
        case source
        case isPrimary
        case createdAt
        case vcsKind
        case currentChangeId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        ownsBranch = try container.decodeIfPresent(Bool.self, forKey: .ownsBranch) ?? false
        source = try container.decodeIfPresent(WorktreeSource.self, forKey: .source) ?? .muxy
        isPrimary = try container.decode(Bool.self, forKey: .isPrimary)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        vcsKind = try container.decodeIfPresent(VcsKind.self, forKey: .vcsKind) ?? .default
        currentChangeId = try container.decodeIfPresent(String.self, forKey: .currentChangeId)
    }
}
```

If the test in Step 1 referenced `JSONDecoder.muxyDecoder` and that namespace doesn't exist, replace those references in the test with plain `JSONDecoder()` instances configured with `.secondsSince1970` Date strategies. Verify by reading existing `ProjectPersistence.swift` to see whether the project has a shared decoder.

- [ ] **Step 4: Run tests**

Run: `swift test --filter WorktreeTolerantDecodeTests`
Expected: 3/3 pass.

Run: `swift test --filter Worktree`
Expected: existing Worktree tests still pass (no behavior regression).

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(vcs): Worktree gains vcsKind + currentChangeId, tolerant v1 decode"
```

---

### Task 3: ProjectPersistence schemaVersion infra

**Files:**
- Modify: `Muxy/Services/ProjectPersistence.swift`
- Test: `Tests/MuxyTests/Services/ProjectsMigrationTests.swift`

This task adds a wrapper envelope around the existing list serialization. v1 = bare array (no envelope); v2 = `{ "schemaVersion": 2, "projects": [...] }`. Reader accepts both forms; writer always emits v2.

- [ ] **Step 1: Read current persistence**

Read `Muxy/Services/ProjectPersistence.swift` and `Muxy/Models/Project.swift` to understand current shape. Note the JSON file path used (likely `~/Library/Application Support/Muxy/projects.json` or similar). Write down (in your scratch space) the current public API.

- [ ] **Step 2: Write the failing tests**

Create `Tests/MuxyTests/Services/ProjectsMigrationTests.swift`:

```swift
import Foundation
import Testing

@testable import Roost

@Suite("ProjectsPersistence schema migration")
struct ProjectsMigrationTests {
    @Test("reads v1 bare array")
    func readsV1() throws {
        let json = """
        [
          {"id": "11111111-1111-1111-1111-111111111111", "name": "Repo", "path": "/Users/me/repo", "createdAt": 776073600}
        ]
        """
        let payload = try ProjectsPersistencePayload.decode(Data(json.utf8))
        #expect(payload.schemaVersion == 1)
        #expect(payload.projects.count == 1)
        #expect(payload.projects[0].name == "Repo")
    }

    @Test("reads v2 envelope")
    func readsV2() throws {
        let json = """
        {
          "schemaVersion": 2,
          "projects": [
            {"id": "11111111-1111-1111-1111-111111111111", "name": "Repo", "path": "/Users/me/repo", "createdAt": 776073600}
          ]
        }
        """
        let payload = try ProjectsPersistencePayload.decode(Data(json.utf8))
        #expect(payload.schemaVersion == 2)
        #expect(payload.projects.count == 1)
    }

    @Test("writer emits v2 envelope")
    func writesV2() throws {
        let payload = ProjectsPersistencePayload(
            schemaVersion: ProjectsPersistencePayload.currentVersion,
            projects: []
        )
        let data = try payload.encode()
        let raw = String(data: data, encoding: .utf8) ?? ""
        #expect(raw.contains("\"schemaVersion\""))
        #expect(raw.contains("\(ProjectsPersistencePayload.currentVersion)"))
    }

    @Test("future version reads as tolerant fallback")
    func futureVersionTolerant() throws {
        let json = """
        {
          "schemaVersion": 999,
          "projects": [
            {"id": "11111111-1111-1111-1111-111111111111", "name": "Repo", "path": "/Users/me/repo", "createdAt": 776073600}
          ]
        }
        """
        let payload = try ProjectsPersistencePayload.decode(Data(json.utf8))
        #expect(payload.schemaVersion == 999)
        #expect(payload.projects.count == 1)
    }
}
```

NOTE: this assumes you'll add a new `ProjectsPersistencePayload` value type. The existing `ProjectPersistence` service is the I/O wrapper; the payload type holds the schema version + project list.

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter ProjectsMigrationTests`
Expected: compile error — `ProjectsPersistencePayload` undefined.

- [ ] **Step 4: Implement payload + integrate with ProjectPersistence**

Add the following to `Muxy/Services/ProjectPersistence.swift` (in addition to the existing class). Place at file scope, not inside the existing class:

```swift
struct ProjectsPersistencePayload: Codable, Sendable {
    static let currentVersion: Int = 2

    let schemaVersion: Int
    let projects: [Project]

    static func decode(_ data: Data) throws -> ProjectsPersistencePayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let envelope = try? decoder.decode(EnvelopeForm.self, from: data) {
            return ProjectsPersistencePayload(
                schemaVersion: envelope.schemaVersion,
                projects: envelope.projects
            )
        }
        let bare = try decoder.decode([Project].self, from: data)
        return ProjectsPersistencePayload(schemaVersion: 1, projects: bare)
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(EnvelopeForm(schemaVersion: schemaVersion, projects: projects))
    }

    private struct EnvelopeForm: Codable {
        let schemaVersion: Int
        let projects: [Project]
    }
}
```

Then update the existing `ProjectPersistence` class methods to read/write through `ProjectsPersistencePayload`:
- Where the existing code reads the file and decodes `[Project]`, replace with `ProjectsPersistencePayload.decode(data).projects`.
- Where the existing code writes, build `ProjectsPersistencePayload(schemaVersion: .currentVersion, projects: list).encode()`.

Read the file first; there may be additional methods (load, save, etc.). Apply minimal-impact edits — preserve the existing public API so callers don't change.

- [ ] **Step 5: Run tests**

Run: `swift test --filter ProjectsMigrationTests`
Expected: 4/4 pass.

Run: `swift test`
Expected: full suite green (existing project store tests still pass through the payload wrapper).

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(persistence): projects.json schemaVersion envelope (v1 tolerant)"
```

---

### Task 4: VcsKindDetector (disk probe)

**Files:**
- Create: `Muxy/Services/VcsKindDetector.swift`
- Test: `Tests/MuxyTests/Services/VcsKindDetectorTests.swift`

Detector is a tiny pure function: probe path for `.jj/` first (jj prefers its own metadata; jj-on-git stores both, but presence of `.jj/` means user is using jj), then `.git` (file or directory — git worktree links are files). Fallback to `.git` if neither is found (treat as future-init or not-yet-initialized; routing decisions in 2.2 will gate behavior).

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import Roost

@Suite("VcsKindDetector")
struct VcsKindDetectorTests {
    private let fm = FileManager.default

    private func makeTempDir() -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("vcsdetect-\(UUID().uuidString)")
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("returns .jj when .jj directory present")
    func detectsJj() throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent(".jj"), withIntermediateDirectories: true)
        #expect(VcsKindDetector.detect(at: dir.path) == .jj)
    }

    @Test("returns .git when .git directory present")
    func detectsGit() throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        #expect(VcsKindDetector.detect(at: dir.path) == .git)
    }

    @Test("returns .git when .git is a file (worktree linkfile)")
    func detectsGitWorktreeLinkfile() throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        let linkfile = dir.appendingPathComponent(".git")
        try "gitdir: /elsewhere/.git/worktrees/x\n".data(using: .utf8)?.write(to: linkfile)
        #expect(VcsKindDetector.detect(at: dir.path) == .git)
    }

    @Test("prefers .jj when both present (jj-on-git colocated)")
    func prefersJj() throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent(".jj"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        #expect(VcsKindDetector.detect(at: dir.path) == .jj)
    }

    @Test("falls back to .git for empty directory")
    func fallback() {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        #expect(VcsKindDetector.detect(at: dir.path) == .git)
    }

    @Test("non-existent path falls back to .git")
    func nonexistent() {
        #expect(VcsKindDetector.detect(at: "/this/path/should/not/exist/abc") == .git)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter VcsKindDetectorTests`
Expected: compile error — `VcsKindDetector` undefined.

- [ ] **Step 3: Implement detector**

Create `Muxy/Services/VcsKindDetector.swift`:

```swift
import Foundation

enum VcsKindDetector {
    static func detect(at path: String) -> VcsKind {
        let fm = FileManager.default
        let jjPath = (path as NSString).appendingPathComponent(".jj")
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: jjPath, isDirectory: &isDir), isDir.boolValue {
            return .jj
        }
        let gitPath = (path as NSString).appendingPathComponent(".git")
        if fm.fileExists(atPath: gitPath) {
            return .git
        }
        return .default
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter VcsKindDetectorTests`
Expected: 6/6 pass.

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(vcs): VcsKindDetector disk-probe (.jj > .git > default)"
```

---

### Task 5: ProjectOpenService writes vcsKind on add

**Files:**
- Modify: `Muxy/Services/ProjectOpenService.swift`
- Modify: `Muxy/Services/WorktreeStore.swift` (or wherever the primary Worktree is constructed when adding a project)

The detector is called when the user adds a project. The detected kind goes onto the primary `Worktree` record. No other behavior changes.

- [ ] **Step 1: Read current code**

Read `Muxy/Services/ProjectOpenService.swift` AND the call site that constructs the primary Worktree (likely in `WorktreeStore` or directly in ProjectOpenService). Identify where today's code creates the primary `Worktree(path: project.path, ..., isPrimary: true)`. That's the insertion point.

- [ ] **Step 2: Write a focused failing test**

Append to `Tests/MuxyTests/Services/VcsKindDetectorTests.swift` (or a new file `Tests/MuxyTests/Services/ProjectOpenVcsKindTests.swift` if you prefer separation):

```swift
@Test("ProjectOpenService stamps vcsKind on primary worktree from detector")
func stampsKindOnAdd() async throws {
    // Construct a temp project dir with .jj/, then call ProjectOpenService.addProject
    // (or whatever the public API is — read the file). Assert the resulting primary
    // Worktree's vcsKind == .jj.
    //
    // If ProjectOpenService is hard to test in isolation (depends on AppState etc),
    // instead split out a tiny pure helper:
    //   `static func detectKind(forPrimaryAt path: String) -> VcsKind`
    // and test that.
}
```

If the existing service is tightly coupled to AppState/ProjectStore and hard to test, extract a static helper `static func resolvePrimaryVcsKind(at path: String) -> VcsKind` in `ProjectOpenService` that wraps `VcsKindDetector.detect(at:)`. Test the helper. Then have the existing add-project code call the helper.

- [ ] **Step 3: Run failing test**

Run: `swift test --filter ProjectOpenVcsKindTests`
Expected: compile error or assertion failure.

- [ ] **Step 4: Wire detector**

In `ProjectOpenService` (or wherever the primary Worktree is built when adding a project), call `VcsKindDetector.detect(at: path)` and pass the result to the `Worktree` initializer's new `vcsKind:` parameter.

If `WorktreeStore` is the construction site, do it there. Either way, the primary Worktree on a freshly added project must have `.vcsKind` set correctly.

For Worktrees created later (subsequent worktrees added via `CreateWorktreeSheet`), inherit the project's primary kind by default — the user can't realistically mix git + jj worktrees inside one project, and jj routing in 2.2 will enforce this.

Concrete: when `WorktreeStore.refreshFromGit` (or any path that creates a `Worktree` instance for an existing project) constructs a `Worktree`, look up the primary worktree's `vcsKind` on that project's worktree list and use it; fall back to detector if no primary yet exists.

- [ ] **Step 5: Run tests**

Run: `swift test --filter Worktree`
Expected: existing tests still pass; new tests pass.

Run: `swift test`
Expected: full suite green.

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(vcs): ProjectOpenService stamps detected VcsKind on primary worktree"
```

---

### Task 6: End-to-end persistence round-trip test

**Files:**
- Modify: `Tests/MuxyTests/Services/ProjectsMigrationTests.swift` (extend with a project + worktree integration test)

This task verifies the full v1 → v2 path: an old `projects.json` (v1, no schemaVersion, Worktrees missing vcsKind) loads, processes through `WorktreePersistence` (worktree files alongside projects.json), and re-writes as v2 with `vcsKind: .git` defaulted.

- [ ] **Step 1: Identify the on-disk layout**

Read `Muxy/Services/WorktreePersistence.swift` to see how worktree files are stored. Likely `<project-id>.json` containing `[Worktree]`. Confirm the directory.

- [ ] **Step 2: Write integration test**

Append to `Tests/MuxyTests/Services/ProjectsMigrationTests.swift`:

```swift
@Test("v1 projects + worktrees round-trip through v2 with defaults")
func endToEndV1RoundTrip() throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("muxy-migration-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let projectsURL = tmp.appendingPathComponent("projects.json")
    let v1ProjectsJson = """
    [
      {"id": "11111111-1111-1111-1111-111111111111", "name": "Repo", "path": "/Users/me/repo", "createdAt": 776073600}
    ]
    """
    try v1ProjectsJson.data(using: .utf8)!.write(to: projectsURL)

    let worktreesDirURL = tmp.appendingPathComponent("worktrees")
    try fm.createDirectory(at: worktreesDirURL, withIntermediateDirectories: true)
    let worktreesURL = worktreesDirURL.appendingPathComponent("11111111-1111-1111-1111-111111111111.json")
    let v1WorktreesJson = """
    [
      {
        "id": "22222222-2222-2222-2222-222222222222",
        "name": "main",
        "path": "/Users/me/repo",
        "branch": "main",
        "ownsBranch": false,
        "source": "muxy",
        "isPrimary": true,
        "createdAt": 776073600
      }
    ]
    """
    try v1WorktreesJson.data(using: .utf8)!.write(to: worktreesURL)

    let projectsData = try Data(contentsOf: projectsURL)
    let projectsPayload = try ProjectsPersistencePayload.decode(projectsData)
    #expect(projectsPayload.schemaVersion == 1)
    #expect(projectsPayload.projects.count == 1)

    let worktreesData = try Data(contentsOf: worktreesURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let worktrees = try decoder.decode([Worktree].self, from: worktreesData)
    #expect(worktrees.count == 1)
    #expect(worktrees[0].vcsKind == .git)
    #expect(worktrees[0].currentChangeId == nil)

    let upgraded = ProjectsPersistencePayload(
        schemaVersion: ProjectsPersistencePayload.currentVersion,
        projects: projectsPayload.projects
    )
    let upgradedData = try upgraded.encode()
    let parsed = try JSONSerialization.jsonObject(with: upgradedData) as? [String: Any]
    #expect(parsed?["schemaVersion"] as? Int == 2)
    #expect(((parsed?["projects"] as? [[String: Any]])?.first?["name"] as? String) == "Repo")
}
```

- [ ] **Step 3: Run the test**

Run: `swift test --filter ProjectsMigrationTests`
Expected: all tests pass (5 total now).

- [ ] **Step 4: Commit**

```bash
jj commit -m "test(persistence): v1 → v2 end-to-end migration round-trip"
```

---

### Task 7: Plan note + final checks

**Files:**
- Modify: `docs/roost-migration-plan.md` (Phase 2 section)

- [ ] **Step 1: Run full Jj + Worktree + Project test filters**

```bash
swift test --filter Jj
swift test --filter Worktree
swift test --filter Project
swift build
```

All should pass. The pre-existing `MuxyURLOpenTests` failures remain orthogonal.

- [ ] **Step 2: Update Phase 2 status block**

Read `docs/roost-migration-plan.md` Phase 2 section. After the "Field mapping" table, append:

```markdown

Phase 2.1 status (2026-04-27):

- VcsKind discriminator added to `Worktree`; tolerant Codable decode keeps v1 payloads loading as `vcsKind = .git` defaulted. Plan: `docs/superpowers/plans/2026-04-27-phase2-1-vcskind-and-projects-migration.md`.
- `projects.json` now wraps in a `{ schemaVersion, projects }` envelope. Reader accepts bare arrays as v1, future versions decode tolerantly.
- `VcsKindDetector` probes `.jj` then `.git` on disk; `ProjectOpenService` stamps the result on the primary Worktree at add time.
- Phase 2.2 (routing) remains: dispatch `WorktreeStore.refresh` and `RemoteServerDelegate.vcsCreateWorktree` by `vcsKind`, and surface jj workspaces in the sidebar.
```

- [ ] **Step 3: Commit**

```bash
jj commit -m "docs(vcs): note Phase 2.1 (VcsKind + persistence migration) landed"
```

---

## Self-Review

**Spec coverage** vs the two design decisions:

| Decision | Covered by |
|----------|-----------|
| D — vcsKind + branch-reuse + currentChangeId | Tasks 1 + 2 |
| C — schemaVersion versioning + tolerant decoder | Task 3 |

**Other spec items**:
- VcsKind detector: Task 4
- Wire-in on project add: Task 5
- Migration round-trip with real on-disk shape: Task 6
- Doc note: Task 7

**Deferred (Phase 2.2)**:
- WorktreeStore.refreshFromGit dispatch
- RemoteServerDelegate vcsCreateWorktree controller protocol
- Sidebar jj workspace listing
- VCSTabState dual-service init
- WorktreeDTO mobile IPC update
- BranchPicker / VCS UI labels

**Placeholder scan**: tests use deterministic literal UUIDs and timestamps; no TODOs.

**Type consistency**: `VcsKind` lives in `Muxy/Models/`; `Worktree.vcsKind: VcsKind`; `VcsKindDetector.detect(at:)` returns `VcsKind`; `ProjectsPersistencePayload.currentVersion: Int = 2`.

---

## Abort criteria

If extending `Worktree` with `vcsKind` triggers a cascade of compile errors across reducers, sidebar views, or VCSTabState (more than ~5 files unexpectedly), **stop**: that means existing code makes pervasive assumptions that warrant a controlled migration in 2.2 first. Pivot the scope of 2.1 to: introduce VcsKind enum + detector + payload envelope only, defer adding vcsKind to Worktree until 2.2.
