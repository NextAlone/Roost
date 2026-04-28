import Foundation
import MuxyShared
import SQLite3

private let sqliteTransient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

actor SessionStore {
    enum StoreError: Error {
        case openFailed(code: Int32, message: String)
        case prepareFailed(code: Int32, message: String)
        case stepFailed(code: Int32, message: String)
    }

    private let url: URL
    nonisolated(unsafe) private var db: OpaquePointer?

    init(url: URL) async throws {
        self.url = url
        try HostdStorage.ensureParentDirectory(for: url)
        try open()
        try migrate()
    }

    deinit {
        if let db {
            sqlite3_close_v2(db)
        }
    }

    private func open() throws {
        var handle: OpaquePointer?
        let path = url.path(percentEncoded: false)
        let result = sqlite3_open_v2(
            path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let handle else {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            if let handle { sqlite3_close_v2(handle) }
            throw StoreError.openFailed(code: result, message: msg)
        }
        self.db = handle
    }

    private func migrate() throws {
        var version: Int32 = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                version = sqlite3_column_int(stmt, 0)
            }
            sqlite3_finalize(stmt)
        }
        if version < 1 {
            try exec("""
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                worktree_id TEXT NOT NULL,
                workspace_path TEXT NOT NULL,
                agent_kind TEXT NOT NULL,
                command TEXT,
                created_at REAL NOT NULL,
                last_state TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS sessions_project ON sessions(project_id);
            CREATE INDEX IF NOT EXISTS sessions_state ON sessions(last_state);
            PRAGMA user_version = 1;
            """)
        }
    }

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let msg = error.map { String(cString: $0) } ?? "exec failed"
            if let error { sqlite3_free(error) }
            throw StoreError.stepFailed(code: result, message: msg)
        }
    }

    func record(_ record: SessionRecord) throws {
        let sql = """
        INSERT OR REPLACE INTO sessions
        (id, project_id, worktree_id, workspace_path, agent_kind, command, created_at, last_state)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        try withStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, record.id.uuidString, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 2, record.projectID.uuidString, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 3, record.worktreeID.uuidString, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 4, record.workspacePath, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 5, record.agentKind.rawValue, -1, sqliteTransient)
            if let command = record.command {
                sqlite3_bind_text(stmt, 6, command, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            sqlite3_bind_double(stmt, 7, record.createdAt.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 8, record.lastState.rawValue, -1, sqliteTransient)
            try step(stmt)
        }
    }

    func update(id: UUID, lastState: SessionLifecycleState) throws {
        let sql = "UPDATE sessions SET last_state = ? WHERE id = ?;"
        try withStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, lastState.rawValue, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 2, id.uuidString, -1, sqliteTransient)
            try step(stmt)
        }
    }

    func list() throws -> [SessionRecord] {
        try query(where: nil)
    }

    func listLive() throws -> [SessionRecord] {
        try query(where: "last_state = 'running'")
    }

    func delete(id: UUID) throws {
        let sql = "DELETE FROM sessions WHERE id = ?;"
        try withStatement(sql) { stmt in
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, sqliteTransient)
            try step(stmt)
        }
    }

    func pruneExited() throws {
        try exec("DELETE FROM sessions WHERE last_state = 'exited';")
    }

    private func query(where clause: String?) throws -> [SessionRecord] {
        var sql = """
        SELECT id, project_id, worktree_id, workspace_path, agent_kind, command, created_at, last_state
        FROM sessions
        """
        if let clause { sql += " WHERE \(clause)" }
        sql += " ORDER BY created_at DESC;"

        var results: [SessionRecord] = []
        try withStatement(sql) { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let record = readRow(stmt) else { continue }
                results.append(record)
            }
        }
        return results
    }

    private func readRow(_ stmt: OpaquePointer?) -> SessionRecord? {
        guard let stmt,
              let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
              let id = UUID(uuidString: idStr),
              let projectStr = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }),
              let projectID = UUID(uuidString: projectStr),
              let worktreeStr = sqlite3_column_text(stmt, 2).map({ String(cString: $0) }),
              let worktreeID = UUID(uuidString: worktreeStr),
              let workspacePath = sqlite3_column_text(stmt, 3).map({ String(cString: $0) }),
              let kindStr = sqlite3_column_text(stmt, 4).map({ String(cString: $0) }),
              let agentKind = AgentKind(rawValue: kindStr),
              let lastStateStr = sqlite3_column_text(stmt, 7).map({ String(cString: $0) }),
              let lastState = SessionLifecycleState(rawValue: lastStateStr)
        else { return nil }
        let command = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))
        return SessionRecord(
            id: id,
            projectID: projectID,
            worktreeID: worktreeID,
            workspacePath: workspacePath,
            agentKind: agentKind,
            command: command,
            createdAt: createdAt,
            lastState: lastState
        )
    }

    private func withStatement(_ sql: String, body: (OpaquePointer?) throws -> Void) throws {
        var stmt: OpaquePointer?
        let prep = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if prep != SQLITE_OK {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "prepare failed"
            sqlite3_finalize(stmt)
            throw StoreError.prepareFailed(code: prep, message: msg)
        }
        defer { sqlite3_finalize(stmt) }
        try body(stmt)
    }

    private func step(_ stmt: OpaquePointer?) throws {
        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "step failed"
            throw StoreError.stepFailed(code: result, message: msg)
        }
    }
}
