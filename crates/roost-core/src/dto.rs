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
    Exited,
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
