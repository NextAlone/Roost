//! Spawn an agent on a fresh PTY and wire up its I/O.
//!
//! Architecture per advisor:
//! - portable-pty's blocking `Read`/`Write` get their own `spawn_blocking`
//!   tasks so tokio worker threads aren't pinned on PTY syscalls.
//! - `Child::wait()` is also blocking → its own `spawn_blocking`.
//! - Reader fan-out: ring buffer (for replay) + tokio broadcast (for live
//!   subscribers).
//! - Writer drains an mpsc; dropping all senders ends the loop and EOFs
//!   stdin (clean kill semantics).

use std::io::{Read, Write};
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

use bytes::Bytes;
use portable_pty::{CommandBuilder, MasterPty, PtySize, native_pty_system};
use roost_core::dto::{AgentSpec, SessionId, SessionInfo, SessionState};
use roost_core::rpc::SessionOscEvent;
use thiserror::Error;
use tokio::sync::{broadcast, mpsc};
use tracing::{info, warn};

use super::osc::OscScanner;
use super::registry::SessionEntry;
use super::ring::{DEFAULT_CAPACITY_BYTES, RingBuffer};
use crate::events::EventBus;

const STDIN_CHANNEL_DEPTH: usize = 64;
const BROADCAST_CHANNEL_DEPTH: usize = 256;
const READ_BUF_SIZE: usize = 4096;

#[derive(Debug, Error)]
pub enum SpawnError {
    #[error("openpty: {0}")]
    OpenPty(String),
    #[error("spawn: {0}")]
    Spawn(String),
    #[error("clone reader: {0}")]
    CloneReader(String),
    #[error("take writer: {0}")]
    TakeWriter(String),
}

pub struct Spawned {
    pub id: SessionId,
    pub entry: SessionEntry,
    pub exited_rx: tokio::sync::oneshot::Receiver<Option<i32>>,
}

/// Open a PTY, exec the agent on the slave, install reader / writer / wait
/// background tasks, return the registry entry for the caller to insert.
///
/// `events`: optional event bus. When `Some`, the reader task feeds an OSC
/// scanner that emits `session_osc` events for whitelisted sequences. None
/// in tests (so the test crate doesn't need to spin up an EventBus).
pub fn spawn_session(spec: AgentSpec, events: Option<EventBus>) -> Result<Spawned, SpawnError> {
    let pty_system = native_pty_system();
    let pair = pty_system
        .openpty(PtySize {
            rows: spec.rows.max(1),
            cols: spec.cols.max(1),
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|e| SpawnError::OpenPty(e.to_string()))?;

    // CommandBuilder via shell so PATH / rc files apply (same reasoning as
    // session::prepare in M6 — agents need user PATH to find siblings).
    let mut cmd = build_command(&spec);
    if !spec.working_directory.is_empty() {
        cmd.cwd(&spec.working_directory);
    }
    for (k, v) in &spec.env {
        cmd.env(k, v);
    }

    let child = pair
        .slave
        .spawn_command(cmd)
        .map_err(|e| SpawnError::Spawn(e.to_string()))?;
    let pid = child.process_id();

    // Slave fd is owned by the child now; closing our handle here is fine
    // (the kernel keeps it open through the child).
    drop(pair.slave);

    let reader = pair
        .master
        .try_clone_reader()
        .map_err(|e| SpawnError::CloneReader(e.to_string()))?;
    let writer = pair
        .master
        .take_writer()
        .map_err(|e| SpawnError::TakeWriter(e.to_string()))?;

    let id = SessionId::new();
    let ring = Arc::new(Mutex::new(RingBuffer::new(DEFAULT_CAPACITY_BYTES)));
    let (broadcast_tx, _) = broadcast::channel::<Bytes>(BROADCAST_CHANNEL_DEPTH);
    let (stdin_tx, stdin_rx) = mpsc::channel::<Bytes>(STDIN_CHANNEL_DEPTH);
    let (resize_tx, resize_rx) = mpsc::unbounded_channel::<(u16, u16)>();

    spawn_reader_task(reader, ring.clone(), broadcast_tx.clone(), id, events.clone());
    spawn_writer_task(writer, stdin_rx, id);
    spawn_resize_task(pair.master, resize_rx, id);
    let exited_rx = spawn_wait_task(child, id);

    let info = SessionInfo {
        id,
        agent_kind: spec.agent_kind.clone(),
        working_directory: spec.working_directory.clone(),
        state: SessionState::Running,
        pid,
        exit_code: None,
        created_at_epoch_ms: now_ms(),
        // Live `list_sessions` callers don't need this — the spec is in
        // memory. History rows from SQLite carry the JSON instead.
        agent_spec_json: None,
    };

    let entry = SessionEntry {
        info,
        stdin_tx: Some(stdin_tx),
        broadcast_tx,
        ring,
        resize_tx: Some(resize_tx),
    };

    Ok(Spawned {
        id,
        entry,
        exited_rx,
    })
}

fn build_command(spec: &AgentSpec) -> CommandBuilder {
    // We expect `spec.command` to already be a single shell-formatted string
    // (e.g. `/bin/zsh -l -c claude`) prepared by `core::session::prepare`.
    // For the empty case (raw shell), default to $SHELL.
    if spec.command.trim().is_empty() {
        let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".into());
        let mut cmd = CommandBuilder::new(shell);
        cmd.arg("-l");
        cmd
    } else {
        // Split on whitespace — adequate because `core::session::prepare`
        // never embeds quoted args. M9 may need a real tokenizer.
        let mut parts = spec.command.split_whitespace();
        let prog = parts.next().expect("non-empty command checked above");
        let mut cmd = CommandBuilder::new(prog);
        for arg in parts {
            cmd.arg(arg);
        }
        cmd
    }
}

fn spawn_reader_task(
    mut reader: Box<dyn Read + Send>,
    ring: Arc<Mutex<RingBuffer>>,
    tx: broadcast::Sender<Bytes>,
    id: SessionId,
    events: Option<EventBus>,
) {
    tokio::task::spawn_blocking(move || {
        let mut buf = [0u8; READ_BUF_SIZE];
        let mut osc = OscScanner::new();
        loop {
            match reader.read(&mut buf) {
                Ok(0) => {
                    info!(%id, "pty reader: EOF");
                    break;
                }
                Ok(n) => {
                    let chunk = &buf[..n];
                    if let Ok(mut g) = ring.lock() {
                        g.push(chunk);
                    }
                    // No subscribers is fine — broadcast::send returns Err
                    // in that case; we don't care.
                    let _ = tx.send(Bytes::copy_from_slice(chunk));

                    // OSC scanning is per-byte but cheap; only allocate
                    // the SessionOscEvent on a hit.
                    if let Some(ev) = events.as_ref() {
                        osc.push(chunk, |seq, payload| {
                            ev.emit_session_osc(SessionOscEvent {
                                session_id: id,
                                seq,
                                payload: payload.to_string(),
                            });
                        });
                    }
                }
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(e) => {
                    warn!(%id, "pty reader error: {e}");
                    break;
                }
            }
        }
    });
}

fn spawn_writer_task(
    mut writer: Box<dyn Write + Send>,
    mut rx: mpsc::Receiver<Bytes>,
    id: SessionId,
) {
    // Bridge async mpsc into blocking writes: a dedicated blocking task that
    // pops via `blocking_recv`. Done this way (rather than spawning blocking
    // *inside* an async loop) so the writer doesn't need to run on a tokio
    // worker.
    tokio::task::spawn_blocking(move || {
        while let Some(chunk) = rx.blocking_recv() {
            if let Err(e) = writer.write_all(&chunk) {
                if e.kind() == std::io::ErrorKind::BrokenPipe {
                    info!(%id, "pty writer: agent closed (EPIPE)");
                } else {
                    warn!(%id, "pty writer error: {e}");
                }
                break;
            }
            if let Err(e) = writer.flush() {
                if e.kind() == std::io::ErrorKind::BrokenPipe {
                    break;
                }
                warn!(%id, "pty writer flush: {e}");
                break;
            }
        }
        // Receiver dropped → no more input. Write loop exits, the master
        // writer drops, and the slave sees EOF on stdin.
    });
}

fn spawn_resize_task(
    master: Box<dyn MasterPty + Send>,
    mut rx: mpsc::UnboundedReceiver<(u16, u16)>,
    id: SessionId,
) {
    // Holding onto `master` here keeps the PTY pair alive across resize calls.
    // We deliberately don't drop it earlier: dropping the master before the
    // writer/reader cleans up triggers ENXIO on the next syscall.
    tokio::task::spawn_blocking(move || {
        while let Some((rows, cols)) = rx.blocking_recv() {
            if let Err(e) = master.resize(PtySize {
                rows: rows.max(1),
                cols: cols.max(1),
                pixel_width: 0,
                pixel_height: 0,
            }) {
                warn!(%id, "pty resize failed: {e}");
            }
        }
        // Channel closed → session being torn down; drop master here so the
        // PTY actually releases. Reader/writer should be done by now.
        drop(master);
    });
}

fn spawn_wait_task(
    mut child: Box<dyn portable_pty::Child + Send + Sync>,
    id: SessionId,
) -> tokio::sync::oneshot::Receiver<Option<i32>> {
    let (tx, rx) = tokio::sync::oneshot::channel();
    tokio::task::spawn_blocking(move || {
        let status = child.wait();
        let code = match status {
            Ok(s) => s.exit_code() as i32,
            Err(e) => {
                warn!(%id, "child wait error: {e}");
                -1
            }
        };
        info!(%id, "child exited code={code}");
        let _ = tx.send(Some(code));
    });
    rx
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;
    use std::time::Duration;

    fn spec(cmd: &str) -> AgentSpec {
        AgentSpec {
            command: cmd.to_string(),
            working_directory: String::new(),
            agent_kind: "shell".into(),
            rows: 24,
            cols: 80,
            env: BTreeMap::new(),
        }
    }

    /// Smoke: spawn `echo roost-pty-smoke`, wait for child exit, snapshot
    /// the ring, assert it contains the marker. Validates the whole chain:
    /// openpty, spawn_command, reader fan-out, ring write, child wait.
    /// Use a single-token argv so `build_command`'s whitespace split lines
    /// up with the test intent (real callers feed `core::session::prepare`
    /// output, which is also single-token-per-arg).
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn smoke_echo_lands_in_ring() {
        let s = spawn_session(spec("/bin/echo roost-pty-smoke"), None).expect("spawn");
        let exit = tokio::time::timeout(Duration::from_secs(5), s.exited_rx)
            .await
            .expect("child exited in time")
            .expect("oneshot recv");
        assert_eq!(exit, Some(0), "bash exit code");

        // Reader runs on spawn_blocking; give it a tick to drain the final
        // bytes after EOF.
        tokio::time::sleep(Duration::from_millis(100)).await;

        let snap = s.entry.ring.lock().unwrap().snapshot();
        let s_str = String::from_utf8_lossy(&snap);
        assert!(
            s_str.contains("roost-pty-smoke"),
            "ring missing marker: {s_str:?}"
        );
    }

    /// Smoke: run `tty` directly — if portable-pty wired up the controlling
    /// terminal correctly the child sees a `/dev/ttys*` path rather than
    /// "not a tty". Cheap fail-fast gate per advisor; catches the class of
    /// platform/version drift where slave_spawn doesn't TIOCSCTTY.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn smoke_child_has_controlling_tty() {
        let s = spawn_session(spec("/usr/bin/tty"), None).expect("spawn");
        tokio::time::timeout(Duration::from_secs(5), s.exited_rx)
            .await
            .expect("child exited in time")
            .expect("oneshot recv");
        tokio::time::sleep(Duration::from_millis(100)).await;

        let snap = s.entry.ring.lock().unwrap().snapshot();
        let s_str = String::from_utf8_lossy(&snap);
        assert!(
            !s_str.contains("not a tty"),
            "child reports no controlling tty: {s_str:?}"
        );
        assert!(
            s_str.contains("/dev/ttys") || s_str.contains("/dev/pts/"),
            "tty did not return a pty path: {s_str:?}"
        );
    }
}
