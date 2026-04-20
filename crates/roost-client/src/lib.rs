//! Synchronous client SDK for talking to `roost-hostd` over Unix socket.
//!
//! Sync `std::os::unix::net::UnixStream` (no tokio) — keeps the staticlib
//! Xcode links lean and avoids a tokio runtime inside the FFI boundary.
//! Per-call connect: open → hello → request → response → close. ~1ms
//! overhead, dominated by the jj CLI spawn it wraps.

mod transport;

pub use roost_core;
pub use roost_core::dto::{HostInfo, RevisionEntry, SessionSpec, StatusEntry, WorkspaceEntry};

use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use roost_core::paths;
use roost_core::rpc::{self, methods, Manifest};
use serde::de::DeserializeOwned;
use serde::Serialize;
use thiserror::Error;
use transport::Conn;

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

/// Stateless handle. Each call opens its own connection — see module doc.
pub struct Client;

impl Client {
    pub fn new() -> Self {
        Self
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

    fn call<P: Serialize, R: DeserializeOwned>(&self, method: &str, params: &P) -> Result<R> {
        let manifest = ensure_hostd()?;
        let mut conn = match Conn::connect(&manifest.socket, &manifest.auth_token, HELLO_TIMEOUT) {
            Ok(c) => c,
            Err(ClientError::Io(_)) | Err(ClientError::Timeout) => {
                // Daemon may have crashed; one retry after respawn.
                let manifest = spawn_and_wait()?;
                Conn::connect(&manifest.socket, &manifest.auth_token, HELLO_TIMEOUT)?
            }
            Err(e) => return Err(e),
        };
        conn.call(method, params, CALL_TIMEOUT)
    }
}

impl Default for Client {
    fn default() -> Self {
        Self::new()
    }
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

    // Detach the daemon: ignore SIGHUP from parent app exit, new session.
    let mut cmd = std::process::Command::new(&bin);
    cmd.stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    unsafe {
        use std::os::unix::process::CommandExt;
        cmd.pre_exec(|| {
            // setsid → new session, detached from controlling terminal.
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

    // Bundle Resources path: when the FFI is invoked from inside Roost.app,
    // the executable is at .../Roost.app/Contents/MacOS/Roost and the daemon
    // is shipped beside it.
    if let Ok(exe) = std::env::current_exe() {
        if let Some(macos_dir) = exe.parent() {
            let beside = macos_dir.join("roost-hostd");
            if beside.is_file() {
                return Some(beside);
            }
            // Resources dir (XcodeGen `buildPhase: resources`):
            // .../Contents/MacOS/Roost → .../Contents/Resources/roost-hostd
            if let Some(contents) = macos_dir.parent() {
                let res = contents.join("Resources").join("roost-hostd");
                if res.is_file() {
                    return Some(res);
                }
            }
        }
    }

    // Dev fallback: walk up from CWD looking for target/{debug,release}/.
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

    // Last-ditch: PATH lookup.
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
