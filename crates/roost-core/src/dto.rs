//! Wire-level data transfer objects, shared between hostd and client.
//!
//! `serde` derive lives on these so JSON-RPC params/results can use them
//! directly. The Swift-facing FFI structs in `roost-bridge` are mirrors.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Opaque session handle. UUID-backed so the wire encoding is stable across
/// hostd restarts (M8 may reattach).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct SessionId(pub Uuid);

impl SessionId {
    pub fn new() -> Self {
        Self(Uuid::new_v4())
    }
}

impl Default for SessionId {
    fn default() -> Self {
        Self::new()
    }
}

impl std::fmt::Display for SessionId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}

impl std::str::FromStr for SessionId {
    type Err = uuid::Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Uuid::parse_str(s).map(SessionId)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionState {
    Starting,
    Running,
    Detached,
    /// Child exited cleanly (or with a known signal). `exit_code` may still
    /// be `Some(-1)` if `Child::wait()` itself errored — that's a wait
    /// failure, not a hostd crash.
    Exited,
    /// Reconciled on hostd startup: SQLite said Running but the in-memory
    /// registry doesn't have it. Hostd crashed (or kill -9'd) since the
    /// session was created — the agent is gone, exit code unknown.
    ExitedLost,
}

impl SessionState {
    pub fn as_str(&self) -> &'static str {
        match self {
            SessionState::Starting => "starting",
            SessionState::Running => "running",
            SessionState::Detached => "detached",
            SessionState::Exited => "exited",
            SessionState::ExitedLost => "exited_lost",
        }
    }
}

impl std::str::FromStr for SessionState {
    type Err = String;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "starting" => Ok(SessionState::Starting),
            "running" => Ok(SessionState::Running),
            "detached" => Ok(SessionState::Detached),
            "exited" => Ok(SessionState::Exited),
            "exited_lost" => Ok(SessionState::ExitedLost),
            other => Err(format!("unknown session state {other:?}")),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentSpec {
    /// Pre-resolved command line. The bridge or CLI runs `core::session::prepare`
    /// to produce this; hostd just executes it.
    pub command: String,
    pub working_directory: String,
    pub agent_kind: String,
    pub rows: u16,
    pub cols: u16,
    #[serde(default)]
    pub env: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionInfo {
    pub id: SessionId,
    pub agent_kind: String,
    pub working_directory: String,
    pub state: SessionState,
    pub pid: Option<u32>,
    pub exit_code: Option<i32>,
    pub created_at_epoch_ms: u64,
    /// Original `AgentSpec` serialized as JSON. Populated when the row
    /// came from `list_session_history`; `None` for live `list_sessions`
    /// responses (the spec is still in memory there). Lets a future
    /// "restart this agent" UX rebuild the spawn arguments faithfully.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_spec_json: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceEntry {
    pub name: String,
    pub path: String,
    pub change_id: String,
    pub description: String,
    pub is_current: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RevisionEntry {
    pub change_id: String,
    pub description: String,
    pub bookmarks: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatusEntry {
    pub clean: bool,
    pub lines: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionSpec {
    pub command: String,
    pub working_directory: String,
    pub agent_kind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HostInfo {
    pub version: String,
    pub pid: u32,
    pub uptime_secs: u64,
    pub session_count: u32,
}
