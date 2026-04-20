//! Synchronous client SDK for talking to `roost-hostd` over Unix socket.
//!
//! M6: per-call connect (stateless). M7: persistent `Connection` so server-
//! pushed events (`session_state`, `session_exited`, `session_osc`) can be
//! observed. The Connection runs a background reader thread (std, not tokio)
//! that demuxes responses by `id` and routes notifications to an events
//! channel.
//!
//! Bridge usage stays sync: `Client::shared()` hands back a singleton that
//! lazily connects (or reconnects after `Disconnected`) and exposes the
//! same typed RPC surface as before.

mod connection;

pub use roost_core;
pub use roost_core::dto::{
    AgentSpec, HostInfo, RevisionEntry, SessionId, SessionInfo, SessionSpec, SessionState,
    StatusEntry, WorkspaceEntry,
};

pub use connection::{Connection, Event};

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use roost_core::paths;
use roost_core::rpc::{self, Manifest, methods};
use serde::Serialize;
use serde::de::DeserializeOwned;
use thiserror::Error;

const HELLO_TIMEOUT: Duration = Duration::from_secs(2);
const CALL_TIMEOUT: Duration = Duration::from_secs(30);
const SPAWN_READY_TIMEOUT: Duration = Duration::from_secs(3);

#[derive(Debug, Error)]
pub enum ClientError {
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),

    #[error("rpc error {code}: {message}")]
    Rpc { code: i32, message: String },

    #[error("hostd version mismatch: server={server}")]
    VersionMismatch { server: String },

    #[error("auth failed: {0}")]
    Auth(String),

    #[error("operation timed out")]
    Timeout,

    #[error("failed to spawn roost-hostd: {0}")]
    Spawn(String),

    #[error("manifest unavailable: {0}")]
    Manifest(String),

    #[error("malformed response: {0}")]
    Decode(String),
}

pub type Result<T> = std::result::Result<T, ClientError>;

pub const CLIENT_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Process-wide handle. The bridge holds one of these for the lifetime of the
/// app; `roost-attach` makes its own (with `Client::new()`).
pub struct Client {
    inner: Mutex<Option<Arc<Connection>>>,
}

static SHARED: OnceLock<Arc<Client>> = OnceLock::new();

impl Client {
    /// Return the process-wide shared client. Use this from FFI / library
    /// callers; only `roost-attach` (which subscribes to events on its own
    /// connection) should call `Client::new()` directly.
    pub fn shared() -> Arc<Client> {
        SHARED
            .get_or_init(|| Arc::new(Client::new()))
            .clone()
    }

    pub fn new() -> Self {
        Self {
            inner: Mutex::new(None),
        }
    }

    /// Get the underlying `Connection`, opening it (and spawning hostd if
    /// needed) on first use; reconnect once if the previous one died.
    pub fn connection(&self) -> Result<Arc<Connection>> {
        let mut g = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(conn) = g.as_ref() {
            if conn.is_alive() {
                return Ok(conn.clone());
            }
        }
        let conn = Arc::new(open_new_connection()?);
        *g = Some(conn.clone());
        Ok(conn)
    }

    fn call<P: Serialize, R: DeserializeOwned>(&self, method: &str, params: &P) -> Result<R> {
        let conn = self.connection()?;
        match conn.call(method, params, CALL_TIMEOUT) {
            Err(ClientError::Io(_)) => {
                // Drop the dead conn and retry once on a freshly spawned hostd.
                {
                    let mut g = self.inner.lock().unwrap_or_else(|p| p.into_inner());
                    *g = None;
                }
                let conn = self.connection()?;
                conn.call(method, params, CALL_TIMEOUT)
            }
            other => other,
        }
    }

    pub fn host_info(&self) -> Result<HostInfo> {
        let r: rpc::HostInfoResult = self.call(methods::HOST_INFO, &rpc::Empty::default())?;
        Ok(r.info)
    }

    pub fn is_jj_repo(&self, dir: &str) -> Result<bool> {
        let r: rpc::IsJjRepoResult = self.call(
            methods::IS_JJ_REPO,
            &rpc::IsJjRepoParams {
                dir: dir.to_string(),
            },
        )?;
        Ok(r.is_jj_repo)
    }

    pub fn jj_version(&self) -> Result<String> {
        let r: rpc::StringResult = self.call(methods::JJ_VERSION, &rpc::Empty::default())?;
        Ok(r.value)
    }

    pub fn list_workspaces(&self, repo_dir: &str) -> Result<Vec<WorkspaceEntry>> {
        let r: rpc::WorkspaceListResult = self.call(
            methods::LIST_WORKSPACES,
            &rpc::RepoDirParams {
                repo_dir: repo_dir.to_string(),
            },
        )?;
        Ok(r.entries)
    }

    pub fn add_workspace(
        &self,
        repo_dir: &str,
        workspace_path: &str,
        name: &str,
    ) -> Result<WorkspaceEntry> {
        let r: rpc::WorkspaceResult = self.call(
            methods::ADD_WORKSPACE,
            &rpc::AddWorkspaceParams {
                repo_dir: repo_dir.into(),
                workspace_path: workspace_path.into(),
                name: name.into(),
            },
        )?;
        Ok(r.entry)
    }

    pub fn forget_workspace(&self, repo_dir: &str, name: &str) -> Result<()> {
        let _: rpc::Empty = self.call(
            methods::FORGET_WORKSPACE,
            &rpc::ForgetWorkspaceParams {
                repo_dir: repo_dir.into(),
                name: name.into(),
            },
        )?;
        Ok(())
    }

    pub fn rename_workspace(&self, workspace_dir: &str, new_name: &str) -> Result<()> {
        let _: rpc::Empty = self.call(
            methods::RENAME_WORKSPACE,
            &rpc::RenameWorkspaceParams {
                workspace_dir: workspace_dir.into(),
                new_name: new_name.into(),
            },
        )?;
        Ok(())
    }

    pub fn update_stale(&self, workspace_dir: &str) -> Result<()> {
        let _: rpc::Empty = self.call(
            methods::UPDATE_STALE,
            &rpc::WorkspaceDirParams {
                workspace_dir: workspace_dir.into(),
            },
        )?;
        Ok(())
    }

    pub fn workspace_root(&self, workspace_dir: &str) -> Result<String> {
        let r: rpc::StringResult = self.call(
            methods::WORKSPACE_ROOT,
            &rpc::WorkspaceDirParams {
                workspace_dir: workspace_dir.into(),
            },
        )?;
        Ok(r.value)
    }

    pub fn current_revision(&self, workspace_dir: &str) -> Result<RevisionEntry> {
        let r: rpc::RevisionResult = self.call(
            methods::CURRENT_REVISION,
            &rpc::WorkspaceDirParams {
                workspace_dir: workspace_dir.into(),
            },
        )?;
        Ok(r.entry)
    }

    pub fn workspace_status(&self, workspace_dir: &str) -> Result<StatusEntry> {
        let r: rpc::StatusResult = self.call(
            methods::WORKSPACE_STATUS,
            &rpc::WorkspaceDirParams {
                workspace_dir: workspace_dir.into(),
            },
        )?;
        Ok(r.entry)
    }

    pub fn bookmark_create(&self, workspace_dir: &str, name: &str) -> Result<()> {
        let _: rpc::Empty = self.call(
            methods::BOOKMARK_CREATE,
            &rpc::BookmarkParams {
                workspace_dir: workspace_dir.into(),
                name: name.into(),
            },
        )?;
        Ok(())
    }

    pub fn bookmark_forget(&self, workspace_dir: &str, name: &str) -> Result<()> {
        let _: rpc::Empty = self.call(
            methods::BOOKMARK_FORGET,
            &rpc::BookmarkParams {
                workspace_dir: workspace_dir.into(),
                name: name.into(),
            },
        )?;
        Ok(())
    }

    // MARK: - Session RPCs (M7)

    pub fn create_session(&self, spec: AgentSpec) -> Result<SessionInfo> {
        let r: rpc::CreateSessionResult =
            self.call(methods::CREATE_SESSION, &rpc::CreateSessionParams { spec })?;
        Ok(r.info)
    }

    pub fn list_sessions(&self) -> Result<Vec<SessionInfo>> {
        let r: rpc::SessionListResult = self.call(methods::LIST_SESSIONS, &rpc::Empty::default())?;
        Ok(r.sessions)
    }

    pub fn kill_session(&self, session_id: SessionId, signal: i32) -> Result<()> {
        let _: rpc::Empty = self.call(
            methods::KILL_SESSION,
            &rpc::KillSessionParams { session_id, signal },
        )?;
        Ok(())
    }

    pub fn resize_session(&self, session_id: SessionId, rows: u16, cols: u16) -> Result<()> {
        let _: rpc::Empty = self.call(
            methods::RESIZE_SESSION,
            &rpc::ResizeSessionParams {
                session_id,
                rows,
                cols,
            },
        )?;
        Ok(())
    }

    pub fn send_input(&self, session_id: SessionId, data: &[u8]) -> Result<()> {
        use base64::{Engine, engine::general_purpose::STANDARD};
        let _: rpc::Empty = self.call(
            methods::SEND_INPUT,
            &rpc::SendInputParams {
                session_id,
                data_b64: STANDARD.encode(data),
            },
        )?;
        Ok(())
    }

    /// Notification-style: hostd ack'd that it received the request, but the
    /// real progress comes via the events channel (`shutdown_progress` /
    /// `shutdown_done`). For Stop, the caller should subscribe to events
    /// before calling and keep the connection alive until `shutdown_done`.
    pub fn shutdown(&self, mode: rpc::ShutdownMode) -> Result<rpc::ShutdownAck> {
        let r: rpc::ShutdownAck =
            self.call(methods::SHUTDOWN, &rpc::ShutdownParams { mode })?;
        Ok(r)
    }

    /// Persisted history (live + exited + exited_lost), most-recent first.
    /// Sourced from the SQLite store, so survives hostd restarts.
    pub fn list_session_history(&self) -> Result<Vec<SessionInfo>> {
        let r: rpc::SessionListResult =
            self.call(methods::LIST_SESSION_HISTORY, &rpc::Empty::default())?;
        Ok(r.sessions)
    }
}

impl Default for Client {
    fn default() -> Self {
        Self::new()
    }
}

fn open_new_connection() -> Result<Connection> {
    let manifest = ensure_hostd()?;
    Connection::connect(&manifest.socket, &manifest.auth_token, HELLO_TIMEOUT)
}

/// Read the manifest. If absent or refers to a dead pid, spawn hostd.
pub fn ensure_hostd() -> Result<Manifest> {
    if let Some(m) = read_manifest_if_alive()? {
        return Ok(m);
    }
    spawn_and_wait()
}

fn read_manifest_if_alive() -> Result<Option<Manifest>> {
    let path = paths::manifest_path();
    if !path.exists() {
        return Ok(None);
    }
    let bytes = match std::fs::read(&path) {
        Ok(b) => b,
        Err(_) => return Ok(None),
    };
    let m: Manifest = match serde_json::from_slice(&bytes) {
        Ok(m) => m,
        Err(_) => return Ok(None),
    };
    if !pid_alive(m.pid) {
        return Ok(None);
    }
    Ok(Some(m))
}

fn pid_alive(pid: u32) -> bool {
    if pid == 0 {
        return false;
    }
    let rc = unsafe { libc::kill(pid as libc::pid_t, 0) };
    if rc == 0 {
        true
    } else {
        std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM)
    }
}

fn spawn_and_wait() -> Result<Manifest> {
    let bin = locate_hostd_binary()
        .ok_or_else(|| ClientError::Spawn("roost-hostd binary not found".into()))?;

    let mut cmd = std::process::Command::new(&bin);
    cmd.stdin(std::process::Stdio::null());
    if let Ok(log_path) = std::env::var("ROOST_HOSTD_SPAWN_LOG") {
        let f = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .ok();
        if let Some(f) = f {
            let f2 = f.try_clone().ok();
            cmd.stdout(std::process::Stdio::from(f));
            if let Some(f2) = f2 {
                cmd.stderr(std::process::Stdio::from(f2));
            }
        } else {
            cmd.stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null());
        }
    } else {
        cmd.stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null());
    }
    unsafe {
        use std::os::unix::process::CommandExt;
        cmd.pre_exec(|| {
            if libc::setsid() == -1 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    cmd.spawn()
        .map_err(|e| ClientError::Spawn(format!("spawn {}: {e}", bin.display())))?;

    let deadline = Instant::now() + SPAWN_READY_TIMEOUT;
    while Instant::now() < deadline {
        if paths::manifest_path().exists() && paths::socket_path().exists() {
            if let Some(m) = read_manifest_if_alive()? {
                return Ok(m);
            }
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    Err(ClientError::Manifest(format!(
        "hostd spawned ({}) but manifest never appeared at {}",
        bin.display(),
        paths::manifest_path().display()
    )))
}

fn locate_hostd_binary() -> Option<PathBuf> {
    if let Ok(p) = std::env::var("ROOST_HOSTD_PATH") {
        let path = PathBuf::from(p);
        if path.is_file() {
            return Some(path);
        }
    }

    if let Ok(exe) = std::env::current_exe() {
        if let Some(macos_dir) = exe.parent() {
            // Sibling in Contents/MacOS/ — production layout (M8 P4).
            let beside = macos_dir.join("roost-hostd");
            if beside.is_file() {
                return Some(beside);
            }
            // Helpers/ + Resources/ — historical layouts kept as fallbacks.
            if let Some(contents) = macos_dir.parent() {
                for sub in &["Helpers", "Resources"] {
                    let candidate = contents.join(sub).join("roost-hostd");
                    if candidate.is_file() {
                        return Some(candidate);
                    }
                }
            }
        }
    }

    let mut cur: PathBuf = std::env::current_dir().ok()?;
    for _ in 0..6 {
        for profile in &["debug", "release"] {
            let candidate = cur.join("target").join(profile).join("roost-hostd");
            if candidate.is_file() {
                return Some(candidate);
            }
        }
        if !cur.pop() {
            break;
        }
    }

    if let Ok(path_var) = std::env::var("PATH") {
        for dir in path_var.split(':') {
            let candidate = Path::new(dir).join("roost-hostd");
            if candidate.is_file() {
                return Some(candidate);
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locate_hostd_honors_env_override_when_file_exists() {
        // Create a temp executable-looking file and point the env at it.
        let tmp = std::env::temp_dir().join(format!(
            "roost-fake-hostd-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::write(&tmp, b"#!/bin/sh\n").unwrap();
        // SAFETY: no other test in this crate reads $ROOST_HOSTD_PATH.
        unsafe { std::env::set_var("ROOST_HOSTD_PATH", tmp.to_string_lossy().as_ref()) };
        let found = locate_hostd_binary();
        unsafe { std::env::remove_var("ROOST_HOSTD_PATH") };
        let _ = std::fs::remove_file(&tmp);
        assert_eq!(found.as_deref(), Some(tmp.as_path()));
    }

    #[test]
    fn locate_hostd_env_override_ignored_when_file_missing() {
        unsafe {
            std::env::set_var(
                "ROOST_HOSTD_PATH",
                "/tmp/roost-definitely-does-not-exist-hostd",
            )
        };
        let found = locate_hostd_binary();
        unsafe { std::env::remove_var("ROOST_HOSTD_PATH") };
        // Falls through to other candidates; the only guarantee is that the
        // sentinel path wasn't returned.
        assert_ne!(
            found.as_deref().map(|p| p.to_string_lossy().into_owned()),
            Some("/tmp/roost-definitely-does-not-exist-hostd".to_string())
        );
    }

    #[test]
    fn pid_zero_is_never_alive() {
        assert!(!pid_alive(0));
    }

    #[test]
    fn pid_self_is_alive() {
        assert!(pid_alive(std::process::id()));
    }
}
