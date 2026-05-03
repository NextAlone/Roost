import Foundation
import MuxyShared
import SQLite3
import Testing

@testable import Roost
@testable import RoostHostdCore

@Suite("SessionStore")
struct SessionStoreTests {
    private func makeTempStoreURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-tests")
            .appendingPathComponent(UUID().uuidString)
        return tmp.appendingPathComponent("sessions.sqlite")
    }

    @Test("record + list round-trip")
    func recordAndList() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let record = SessionRecord(
            id: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .claudeCode,
            command: "claude",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastState: .running
        )
        try await store.record(record)
        let all = try await store.list()
        #expect(all.count == 1)
        #expect(all.first?.id == record.id)
        #expect(all.first?.agentKind == .claudeCode)
        #expect(all.first?.command == "claude")
        #expect(all.first?.lastState == .running)
    }

    @Test("update changes lastState only")
    func updateLastState() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let record = SessionRecord(
            id: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .codex,
            command: "codex",
            createdAt: Date(),
            lastState: .running
        )
        try await store.record(record)
        try await store.update(id: record.id, lastState: .exited)
        let all = try await store.list()
        #expect(all.first?.lastState == .exited)
    }

    @Test("listLive filters to running sessions")
    func listLive() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)

        let live = SessionRecord(id: UUID(), projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/a", agentKind: .terminal, command: nil, createdAt: Date(), lastState: .running)
        let dead = SessionRecord(id: UUID(), projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/b", agentKind: .terminal, command: nil, createdAt: Date(), lastState: .exited)
        try await store.record(live)
        try await store.record(dead)

        let liveList = try await store.listLive()
        #expect(liveList.count == 1)
        #expect(liveList.first?.id == live.id)
    }

    @Test("delete removes a record")
    func deletes() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let record = SessionRecord(id: UUID(), projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/wt", agentKind: .terminal, command: nil, createdAt: Date(), lastState: .running)
        try await store.record(record)
        try await store.delete(id: record.id)
        let all = try await store.list()
        #expect(all.isEmpty)
    }

    @Test("pruneExited removes only exited records")
    func pruneExited() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let live = SessionRecord(id: UUID(), projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/a", agentKind: .terminal, command: nil, createdAt: Date(), lastState: .running)
        let dead = SessionRecord(id: UUID(), projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/b", agentKind: .terminal, command: nil, createdAt: Date(), lastState: .exited)
        try await store.record(live)
        try await store.record(dead)
        try await store.pruneExited()
        let all = try await store.list()
        #expect(all.count == 1)
        #expect(all.first?.id == live.id)
    }

    @Test("re-opening the same db file preserves records")
    func persistsAcrossOpens() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store1 = try await SessionStore(url: url)
        let record = SessionRecord(id: UUID(), projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/wt", agentKind: .codex, command: "codex", createdAt: Date(), lastState: .running)
        try await store1.record(record)
        let store2 = try await SessionStore(url: url)
        let all = try await store2.list()
        #expect(all.count == 1)
        #expect(all.first?.id == record.id)
    }

    @Test("record waits for a transient external write lock")
    func waitsForTransientExternalWriteLock() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let lock = try SQLiteWriteLock(url: url)
        defer { lock.close() }
        try lock.beginImmediate()

        let record = SessionRecord(
            id: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .codex,
            command: "codex",
            createdAt: Date(),
            lastState: .running
        )
        let task = Task {
            try await store.record(record)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        try lock.commit()
        try await task.value

        let all = try await store.list()
        #expect(all.map(\.id) == [record.id])
    }
}

private final class SQLiteWriteLock {
    private var db: OpaquePointer?

    init(url: URL) throws {
        let result = sqlite3_open_v2(
            url.path(percentEncoded: false),
            &db,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            throw SessionStore.StoreError.openFailed(code: result, message: msg)
        }
    }

    func beginImmediate() throws {
        try exec("BEGIN IMMEDIATE;")
    }

    func commit() throws {
        try exec("COMMIT;")
    }

    func close() {
        if let db {
            sqlite3_close_v2(db)
            self.db = nil
        }
    }

    private func exec(_ sql: String) throws {
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "exec failed"
            throw SessionStore.StoreError.stepFailed(code: result, message: msg)
        }
    }
}
