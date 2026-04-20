//! JSON-RPC 2.0 wire protocol, newline-delimited frames over Unix sockets.
//!
//! Design locked in design.md §4. Frames are single-line UTF-8 JSON with a
//! terminating `\n`; one request per frame, one response per frame, no
//! batching. Client must send `hello` first, which is NOT a JSON-RPC request
//! (it has no `method`/`id` — it's a handshake envelope). After a valid hello,
//! regular JSON-RPC exchange begins.

use serde::{Deserialize, Serialize};

use crate::dto::{
    AgentSpec, HostInfo, RevisionEntry, SessionId, SessionInfo, SessionSpec, SessionState,
    StatusEntry, WorkspaceEntry,
};

/// Handshake envelope sent by the client as the very first frame on a fresh
/// **control** connection. `auth_token` must match the manifest;
/// `client_version` must match hostd on MAJOR.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hello {
    pub auth_token: String,
    pub client_version: String,
}

/// First frame on a **data** connection. Hostd identifies the connection
/// type by trying to parse this first; on success it switches to raw byte
/// passthrough (replaying the session's ring, then live broadcast).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttachHello {
    pub auth_token: String,
    pub session_id: SessionId,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttachAck {
    pub ok: bool,
    pub server_version: String,
    pub error: Option<String>,
    /// Bytes the client should treat as scrollback (UTF-8 lossy ok).
    /// Sent inline as base64 so the data conn stays line-delimited until
    /// the very next byte (raw stream begins immediately after this frame).
    /// Empty if the ring is empty.
    #[serde(default)]
    pub replay_b64: String,
}

/// Hostd's reply to `Hello`. On success, `ok=true` and the rest is informational.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HelloAck {
    pub ok: bool,
    pub server_version: String,
    pub error: Option<String>,
}

/// A JSON-RPC 2.0 request frame. `params` are untyped at the wire layer; the
/// server's dispatch decodes them per `method`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Request {
    pub jsonrpc: String,
    pub id: u64,
    pub method: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub params: Option<serde_json::Value>,
}

impl Request {
    pub fn new(id: u64, method: impl Into<String>, params: impl Serialize) -> Self {
        Self {
            jsonrpc: "2.0".into(),
            id,
            method: method.into(),
            params: Some(serde_json::to_value(params).expect("serialize params")),
        }
    }
}

/// A JSON-RPC 2.0 response frame. Exactly one of `result`/`error` is set.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Response {
    pub jsonrpc: String,
    pub id: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<RpcError>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
}

impl RpcError {
    pub fn method_not_found(method: &str) -> Self {
        Self {
            code: error_codes::METHOD_NOT_FOUND,
            message: format!("method '{method}' not found"),
        }
    }

    pub fn invalid_params(msg: impl Into<String>) -> Self {
        Self {
            code: error_codes::INVALID_PARAMS,
            message: msg.into(),
        }
    }

    pub fn internal(msg: impl Into<String>) -> Self {
        Self {
            code: error_codes::INTERNAL,
            message: msg.into(),
        }
    }

    pub fn panic(msg: impl Into<String>) -> Self {
        Self {
            code: error_codes::INTERNAL_PANIC,
            message: msg.into(),
        }
    }

    pub fn domain(msg: impl Into<String>) -> Self {
        Self {
            code: error_codes::DOMAIN,
            message: msg.into(),
        }
    }
}

pub mod error_codes {
    pub const PARSE_ERROR: i32 = -32700;
    pub const INVALID_REQUEST: i32 = -32600;
    pub const METHOD_NOT_FOUND: i32 = -32601;
    pub const INVALID_PARAMS: i32 = -32602;
    pub const INTERNAL: i32 = -32603;
    // Server-reserved -32000..-32099
    pub const INTERNAL_PANIC: i32 = -32000;
    pub const DOMAIN: i32 = -32001;
    pub const AUTH_FAILED: i32 = -32002;
    pub const VERSION_MISMATCH: i32 = -32003;
}

pub mod methods {
    pub const HOST_INFO: &str = "host_info";
    pub const IS_JJ_REPO: &str = "is_jj_repo";
    pub const JJ_VERSION: &str = "jj_version";
    pub const LIST_WORKSPACES: &str = "list_workspaces";
    pub const ADD_WORKSPACE: &str = "add_workspace";
    pub const FORGET_WORKSPACE: &str = "forget_workspace";
    pub const RENAME_WORKSPACE: &str = "rename_workspace";
    pub const UPDATE_STALE: &str = "update_stale";
    pub const WORKSPACE_ROOT: &str = "workspace_root";
    pub const CURRENT_REVISION: &str = "current_revision";
    pub const WORKSPACE_STATUS: &str = "workspace_status";
    pub const BOOKMARK_CREATE: &str = "bookmark_create";
    pub const BOOKMARK_FORGET: &str = "bookmark_forget";

    // Sessions (M7).
    pub const CREATE_SESSION: &str = "create_session";
    pub const LIST_SESSIONS: &str = "list_sessions";
    pub const KILL_SESSION: &str = "kill_session";
    pub const RESIZE_SESSION: &str = "resize_session";
    pub const SEND_INPUT: &str = "send_input";

    // Daemon lifecycle (M8).
    pub const SHUTDOWN: &str = "shutdown";
}

/// Server→client notification method names (sent as JSON-RPC frames with
/// `method` and no `id`).
pub mod events {
    pub const SESSION_STATE: &str = "session_state";
    pub const SESSION_EXITED: &str = "session_exited";
    pub const SESSION_OSC: &str = "session_osc";

    // Daemon shutdown progress (M8). `shutdown_progress` fires per session
    // termination during a Stop; `shutdown_done` fires once before exit.
    pub const SHUTDOWN_PROGRESS: &str = "shutdown_progress";
    pub const SHUTDOWN_DONE: &str = "shutdown_done";
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IsJjRepoParams {
    pub dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IsJjRepoResult {
    pub is_jj_repo: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DirParams {
    pub dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepoDirParams {
    pub repo_dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AddWorkspaceParams {
    pub repo_dir: String,
    pub workspace_path: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ForgetWorkspaceParams {
    pub repo_dir: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenameWorkspaceParams {
    pub workspace_dir: String,
    pub new_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceDirParams {
    pub workspace_dir: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BookmarkParams {
    pub workspace_dir: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StringResult {
    pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceListResult {
    pub entries: Vec<WorkspaceEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceResult {
    pub entry: WorkspaceEntry,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RevisionResult {
    pub entry: RevisionEntry,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatusResult {
    pub entry: StatusEntry,
}

/// Manifest on disk, 0600. Written by hostd on startup, consumed by client.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    pub pid: u32,
    pub socket: String,
    pub auth_token: String,
    pub version: String,
    pub started_at_epoch_ms: u64,
}

/// Major-version compare helper: `"0.1.2"` → `"0"`. Minor drift = warn, major
/// drift = reject.
pub fn major_of(version: &str) -> &str {
    version.split('.').next().unwrap_or(version)
}

/// Unused today (no PTY RPCs yet) but reserved for M7.
#[allow(dead_code)]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionSpecResult {
    pub spec: SessionSpec,
}

// MARK: - Session params/results (M7)

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateSessionParams {
    pub spec: AgentSpec,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreateSessionResult {
    pub info: SessionInfo,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionListResult {
    pub sessions: Vec<SessionInfo>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KillSessionParams {
    pub session_id: SessionId,
    /// POSIX signal number. Hostd default to SIGTERM if 0/missing.
    #[serde(default)]
    pub signal: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResizeSessionParams {
    pub session_id: SessionId,
    pub rows: u16,
    pub cols: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SendInputParams {
    pub session_id: SessionId,
    /// base64 of the raw bytes to feed to the agent's stdin. Optional
    /// path; data conn is preferred for high-bandwidth I/O.
    pub data_b64: String,
}

// MARK: - Event payloads

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionStateEvent {
    pub session_id: SessionId,
    pub state: SessionState,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionExitedEvent {
    pub session_id: SessionId,
    pub exit_code: Option<i32>,
}

// MARK: - Daemon shutdown (M8)

/// `release` = app disconnects, hostd keeps running and agents stay alive
/// (manifest stays on disk so the next launch adopts).
/// `stop` = SIGTERM all sessions with grace, then SIGKILL stragglers,
/// remove manifest, exit. Notification-only RPC; the real progress comes
/// over `shutdown_progress` / `shutdown_done` events.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ShutdownMode {
    Release,
    Stop,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShutdownParams {
    pub mode: ShutdownMode,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShutdownAck {
    /// Hint for the client UI ("Stopping 3 agents…"). Live count at the
    /// moment shutdown was requested; subsequent events are the truth.
    pub live_sessions: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShutdownProgressEvent {
    pub remaining_sessions: u32,
    pub elapsed_ms: u64,
    /// The session that just exited (None for the initial 0 → live_sessions
    /// progress tick, if any).
    pub last_session_id: Option<SessionId>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShutdownDoneEvent {
    pub forced_kills: u32,
    pub elapsed_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionOscEvent {
    pub session_id: SessionId,
    /// OSC sequence number (9, 99, 777, ...). The bridge / UI cares only
    /// about a small whitelist; non-whitelisted OSCs aren't broadcast.
    pub seq: u32,
    /// Payload between `;` and the OSC terminator. Sent as plain string;
    /// non-UTF8 input is replaced with U+FFFD.
    pub payload: String,
}

/// Unused today (host_info has no params) but keeps call sites symmetric.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Empty {}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HostInfoResult {
    #[serde(flatten)]
    pub info: HostInfo,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn major_of_extracts_first_component() {
        assert_eq!(major_of("0.1.0"), "0");
        assert_eq!(major_of("1.2.3"), "1");
        assert_eq!(major_of("10.0.0-alpha"), "10");
    }

    #[test]
    fn major_of_handles_missing_dots() {
        // Unusual but shouldn't panic — return the whole input.
        assert_eq!(major_of("abc"), "abc");
        assert_eq!(major_of(""), "");
    }

    #[test]
    fn major_compare_rejects_cross_major() {
        // Client on 0.x, server on 1.x → major mismatch even if minor is 0.
        assert_ne!(major_of("0.9.9"), major_of("1.0.0"));
    }

    #[test]
    fn major_compare_accepts_same_major_minor_drift() {
        // 0.1 vs 0.2 → minor drift, same major.
        assert_eq!(major_of("0.1.0"), major_of("0.2.7"));
    }

    #[test]
    fn rpc_error_helpers_tag_codes_correctly() {
        assert_eq!(RpcError::invalid_params("x").code, error_codes::INVALID_PARAMS);
        assert_eq!(RpcError::internal("y").code, error_codes::INTERNAL);
        assert_eq!(RpcError::domain("z").code, error_codes::DOMAIN);
        assert_eq!(RpcError::panic("p").code, error_codes::INTERNAL_PANIC);
        assert_eq!(RpcError::method_not_found("m").code, error_codes::METHOD_NOT_FOUND);
    }
}
