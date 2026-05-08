import Foundation
import MuxyShared
import SQLite3
@testable import RoostHostdCore
import Testing

@Suite("SessionStore migration v2")
struct SessionStoreMigrationTests {
    private func makeTempStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-tests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("sessions.sqlite")
    }

    @Test("openDatabase adds last_tail column")
    func openDatabaseAddsLastTailColumn() async throws {
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
            lastState: .running,
            lastTail: "captured tail line"
        )
        try await store.record(record)
        let read = try await store.list().first { $0.id == record.id }
        #expect(read?.lastTail == "captured tail line")
    }

    @Test("nil lastTail round trips")
    func nilLastTailRoundTrips() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = try await SessionStore(url: url)
        let record = SessionRecord(
            id: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .terminal,
            command: nil,
            createdAt: Date(),
            lastState: .running,
            lastTail: nil
        )
        try await store.record(record)
        let read = try await store.list().first { $0.id == record.id }
        #expect(read?.lastTail == nil)
    }

    @Test("legacy v1 database upgrades to v2 and reads existing rows with nil lastTail")
    func legacyV1DatabaseUpgrades() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let legacyID = UUID()
        let legacyProjectID = UUID()
        let legacyWorktreeID = UUID()
        let legacyCreatedAt: TimeInterval = 1_700_000_500
        try seedLegacyV1Database(
            at: url,
            id: legacyID,
            projectID: legacyProjectID,
            worktreeID: legacyWorktreeID,
            createdAt: legacyCreatedAt
        )

        let store = try await SessionStore(url: url)
        let all = try await store.list()
        let legacy = all.first { $0.id == legacyID }
        #expect(legacy != nil)
        #expect(legacy?.lastTail == nil)
        #expect(legacy?.workspacePath == "/tmp/legacy")
        #expect(legacy?.agentKind == .codex)
        #expect(legacy?.lastState == .running)

        let upgraded = SessionRecord(
            id: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/new",
            agentKind: .terminal,
            command: nil,
            createdAt: Date(),
            lastState: .running,
            lastTail: "tail after upgrade"
        )
        try await store.record(upgraded)
        let readBack = try await store.list().first { $0.id == upgraded.id }
        #expect(readBack?.lastTail == "tail after upgrade")
    }

    private func seedLegacyV1Database(
        at url: URL,
        id: UUID,
        projectID: UUID,
        worktreeID: UUID,
        createdAt: TimeInterval
    ) throws {
        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            url.path(percentEncoded: false),
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let handle else {
            if let handle { sqlite3_close_v2(handle) }
            throw SessionStore.StoreError.openFailed(code: openResult, message: "seed open failed")
        }
        defer { sqlite3_close_v2(handle) }

        let schemaSQL = """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            worktree_id TEXT NOT NULL,
            workspace_path TEXT NOT NULL,
            agent_kind TEXT NOT NULL,
            command TEXT,
            created_at REAL NOT NULL,
            last_state TEXT NOT NULL
        );
        CREATE INDEX sessions_project ON sessions(project_id);
        CREATE INDEX sessions_state ON sessions(last_state);
        PRAGMA user_version = 1;
        """
        var schemaError: UnsafeMutablePointer<CChar>?
        let schemaResult = sqlite3_exec(handle, schemaSQL, nil, nil, &schemaError)
        if schemaResult != SQLITE_OK {
            let msg = schemaError.map { String(cString: $0) } ?? "schema exec failed"
            if let schemaError { sqlite3_free(schemaError) }
            throw SessionStore.StoreError.stepFailed(code: schemaResult, message: msg)
        }

        let insertSQL = """
        INSERT INTO sessions
        (id, project_id, worktree_id, workspace_path, agent_kind, command, created_at, last_state)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        let prep = sqlite3_prepare_v2(handle, insertSQL, -1, &stmt, nil)
        if prep != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(handle))
            sqlite3_finalize(stmt)
            throw SessionStore.StoreError.prepareFailed(code: prep, message: msg)
        }
        let transient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, transient)
        sqlite3_bind_text(stmt, 2, projectID.uuidString, -1, transient)
        sqlite3_bind_text(stmt, 3, worktreeID.uuidString, -1, transient)
        sqlite3_bind_text(stmt, 4, "/tmp/legacy", -1, transient)
        sqlite3_bind_text(stmt, 5, AgentKind.codex.rawValue, -1, transient)
        sqlite3_bind_text(stmt, 6, "codex", -1, transient)
        sqlite3_bind_double(stmt, 7, createdAt)
        sqlite3_bind_text(stmt, 8, SessionLifecycleState.running.rawValue, -1, transient)
        let stepResult = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        guard stepResult == SQLITE_DONE else {
            let msg = String(cString: sqlite3_errmsg(handle))
            throw SessionStore.StoreError.stepFailed(code: stepResult, message: msg)
        }
    }
}
