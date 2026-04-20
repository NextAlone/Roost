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
        let result = roost_is_jj_repo(dir)
        NSLog("[Roost] isJjRepo dir=%@ result=%d", dir, result ? 1 : 0)
        return result
    }

    static func jjVersion() throws -> String {
        try roost_jj_version().toString()
    }

    static func listWorkspaces(repoDir: String) throws -> [WorkspaceEntrySwift] {
        let serialized = try roost_list_workspaces_serialized(repoDir).toString()
        return serialized
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap(WorkspaceEntrySwift.init(serializedRow:))
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

    init(name: String, path: String, changeId: String, description: String, isCurrent: Bool) {
        self.name = name
        self.path = path
        self.changeId = changeId
        self.description = description
        self.isCurrent = isCurrent
    }

    init(raw: WorkspaceEntry) {
        self.init(
            name: raw.name.toString(),
            path: raw.path.toString(),
            changeId: raw.change_id.toString(),
            description: raw.description.toString(),
            isCurrent: raw.is_current
        )
    }

    /// Parse a `\u{1f}`-delimited row from `roost_list_workspaces_serialized`.
    init?<S: StringProtocol>(serializedRow row: S) {
        let fields = row.split(separator: "\u{1f}", omittingEmptySubsequences: false)
        guard fields.count >= 5 else { return nil }
        self.init(
            name: String(fields[0]),
            path: String(fields[1]),
            changeId: String(fields[2]),
            description: String(fields[3]),
            isCurrent: fields[4] == "1"
        )
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
