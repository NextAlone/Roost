//! Manifest + socket on-disk lifecycle.
//!
//! Pre-start reconciliation is the only safety net for M6 (full adopt UX is
//! M8). If a stale manifest references a dead pid, we unlink it and the
//! socket; if the pid is still alive, we refuse to start so we don't trample
//! a running daemon.

use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use roost_core::paths;
use roost_core::rpc::Manifest;
use tokio::fs;
use tracing::{info, warn};

pub async fn reconcile_stale() -> Result<()> {
    let mpath = paths::manifest_path();
    if !mpath.exists() {
        // Socket might still be on disk from an even older crash; clean up.
        cleanup_socket().await;
        return Ok(());
    }

    let bytes = match fs::read(&mpath).await {
        Ok(b) => b,
        Err(e) => {
            warn!("manifest unreadable ({e}); removing");
            let _ = fs::remove_file(&mpath).await;
            cleanup_socket().await;
            return Ok(());
        }
    };

    let manifest: Manifest = match serde_json::from_slice(&bytes) {
        Ok(m) => m,
        Err(e) => {
            warn!("manifest unparseable ({e}); removing");
            let _ = fs::remove_file(&mpath).await;
            cleanup_socket().await;
            return Ok(());
        }
    };

    if pid_alive(manifest.pid) {
        bail!(
            "another roost-hostd is already running (pid={}, manifest={}). \
             stop it first or remove the manifest manually.",
            manifest.pid,
            mpath.display()
        );
    }

    info!(
        "stale manifest for dead pid {}; cleaning up",
        manifest.pid
    );
    let _ = fs::remove_file(&mpath).await;
    cleanup_socket().await;
    Ok(())
}

async fn cleanup_socket() {
    let s = paths::socket_path();
    if s.exists() {
        let _ = fs::remove_file(&s).await;
    }
}

fn pid_alive(pid: u32) -> bool {
    if pid == 0 {
        return false;
    }
    // SAFETY: kill(pid, 0) is the standard POSIX liveness probe; signal 0
    // performs error checking (ESRCH = dead, EPERM = alive but not ours).
    let rc = unsafe { libc::kill(pid as libc::pid_t, 0) };
    if rc == 0 {
        true
    } else {
        let err = std::io::Error::last_os_error();
        err.raw_os_error() == Some(libc::EPERM)
    }
}

/// Atomic 0600 write: tmp + rename.
pub async fn write(manifest: &Manifest) -> Result<()> {
    let dir = paths::hostd_dir();
    fs::create_dir_all(&dir).await.with_context(|| {
        format!("create hostd dir {}", dir.display())
    })?;
    set_dir_perms(&dir).await?;

    let final_path = paths::manifest_path();
    let tmp_path = dir.join("manifest.json.tmp");
    let bytes = serde_json::to_vec_pretty(manifest)?;
    fs::write(&tmp_path, bytes).await.with_context(|| {
        format!("write {}", tmp_path.display())
    })?;
    let mut perms = fs::metadata(&tmp_path).await?.permissions();
    perms.set_mode(0o600);
    fs::set_permissions(&tmp_path, perms).await?;
    fs::rename(&tmp_path, &final_path).await.with_context(|| {
        format!("rename {} -> {}", tmp_path.display(), final_path.display())
    })?;
    info!("manifest written at {}", final_path.display());
    Ok(())
}

async fn set_dir_perms(dir: &Path) -> Result<()> {
    let mut perms = fs::metadata(dir).await?.permissions();
    perms.set_mode(0o700);
    fs::set_permissions(dir, perms).await?;
    Ok(())
}

pub async fn remove() {
    let _ = fs::remove_file(paths::manifest_path()).await;
    let _ = fs::remove_file(paths::socket_path()).await;
}

/// Bounded wait for the manifest + socket to land — used by the client when it
/// just spawned hostd and needs to know when it's ready.
#[allow(dead_code)]
pub async fn wait_for_ready(timeout: Duration) -> bool {
    let deadline = std::time::Instant::now() + timeout;
    while std::time::Instant::now() < deadline {
        if paths::manifest_path().exists() && paths::socket_path().exists() {
            return true;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    false
}
