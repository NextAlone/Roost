//! Wire-level data transfer objects, shared between hostd and client.
//!
//! `serde` derive lives on these so JSON-RPC params/results can use them
//! directly. The Swift-facing FFI structs in `roost-bridge` are mirrors.

use serde::{Deserialize, Serialize};

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
