import Foundation

/// Swift-facing facade over the generated swift-bridge bindings in
/// `Generated/RoostBridge.swift`. Wraps `RustString` / `RustVec` returns in
/// Swift-native types so callers don't touch swift-bridge internals and
/// never hold on to FFI ownership-carrying types.
enum RoostBridge {
    // MARK: Smoke + sessions

    static var version: String {
        roost_bridge_version().toString()
    }

    static func greet(_ name: String) -> String {
        roost_greet(name).toString()
    }

    static func prepareSession(agent: String) -> SessionSpecSwift {
        SessionSpecSwift(raw: roost_prepare_session(agent))
    }

    static func prepareSession(agent: String, workingDirectory: String) -> SessionSpecSwift {
        SessionSpecSwift(raw: roost_prepare_session_in(agent, workingDirectory))
    }

    // MARK: jj

    static func isJjRepo(dir: String) -> Bool {
        roost_is_jj_repo(dir)
    }

    static func jjVersion() throws -> String {
        try roost_jj_version().toString()
    }

    static func listWorkspaces(repoDir: String) throws -> [WorkspaceEntrySwift] {
        let vec = try roost_list_workspaces(repoDir)
        var out: [WorkspaceEntrySwift] = []
        out.reserveCapacity(Int(vec.len()))
        for i in 0..<vec.len() {
            if let item = vec.get(index: i) {
                out.append(WorkspaceEntrySwift(raw: item))
            }
        }
        return out
    }

    static func addWorkspace(
        repoDir: String,
        workspacePath: String,
        name: String
    ) throws -> WorkspaceEntrySwift {
        WorkspaceEntrySwift(raw: try roost_add_workspace(repoDir, workspacePath, name))
    }

    static func forgetWorkspace(repoDir: String, name: String) throws {
        try roost_forget_workspace(repoDir, name)
    }

    static func renameWorkspace(workspaceDir: String, newName: String) throws {
        try roost_rename_workspace(workspaceDir, newName)
    }

    static func updateStale(workspaceDir: String) throws {
        try roost_update_stale(workspaceDir)
    }

    static func workspaceRoot(workspaceDir: String) throws -> String {
        try roost_workspace_root(workspaceDir).toString()
    }

    static func currentRevision(workspaceDir: String) throws -> RevisionEntrySwift {
        RevisionEntrySwift(raw: try roost_current_revision(workspaceDir))
    }

    static func workspaceStatus(workspaceDir: String) throws -> StatusEntrySwift {
        StatusEntrySwift(raw: try roost_workspace_status(workspaceDir))
    }

    static func bookmarkCreate(workspaceDir: String, name: String) throws {
        try roost_bookmark_create(workspaceDir, name)
    }

    static func bookmarkForget(workspaceDir: String, name: String) throws {
        try roost_bookmark_forget(workspaceDir, name)
    }
}

// MARK: - Swift-native mirrors of shared structs

struct SessionSpecSwift: Equatable {
    let command: String
    let workingDirectory: String
    let agentKind: String

    init(command: String, workingDirectory: String, agentKind: String) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.agentKind = agentKind
    }

    init(raw: SessionSpec) {
        self.init(
            command: raw.command.toString(),
            workingDirectory: raw.working_directory.toString(),
            agentKind: raw.agent_kind.toString()
        )
    }
}

struct WorkspaceEntrySwift: Equatable, Identifiable, Hashable {
    let name: String
    let path: String
    let changeId: String
    let description: String
    let isCurrent: Bool

    var id: String { name }

    init(raw: WorkspaceEntry) {
        self.name = raw.name.toString()
        self.path = raw.path.toString()
        self.changeId = raw.change_id.toString()
        self.description = raw.description.toString()
        self.isCurrent = raw.is_current
    }
}

struct RevisionEntrySwift: Equatable {
    let changeId: String
    let description: String
    let bookmarks: [String]

    init(raw: RevisionEntry) {
        self.changeId = raw.change_id.toString()
        self.description = raw.description.toString()
        let csv = raw.bookmarks_csv.toString()
        self.bookmarks = csv.isEmpty
            ? []
            : csv.split(separator: ",").map(String.init)
    }
}

struct StatusEntrySwift: Equatable {
    let clean: Bool
    let text: String

    init(raw: StatusEntry) {
        self.clean = raw.clean
        self.text = raw.text.toString()
    }
}
