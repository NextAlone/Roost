//! JSON-RPC 2.0 wire protocol, newline-delimited frames over Unix sockets.
//!
//! Design locked in design.md §4. Frames are single-line UTF-8 JSON with a
//! terminating `\n`; one request per frame, one response per frame, no
//! batching. Client must send `hello` first, which is NOT a JSON-RPC request
//! (it has no `method`/`id` — it's a handshake envelope). After a valid hello,
//! regular JSON-RPC exchange begins.

use serde::{Deserialize, Serialize};

use crate::dto::{HostInfo, RevisionEntry, SessionSpec, StatusEntry, WorkspaceEntry};

/// Handshake envelope sent by the client as the very first frame on a fresh
/// connection. `auth_token` must match the manifest; `client_version` must
/// match hostd on MAJOR.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hello {
    pub auth_token: String,
    pub client_version: String,
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

/// Unused today (host_info has no params) but keeps call sites symmetric.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Empty {}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HostInfoResult {
    #[serde(flatten)]
    pub info: HostInfo,
}
