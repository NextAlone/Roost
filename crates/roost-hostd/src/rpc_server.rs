//! UDS listener + connection multiplexer.
//!
//! Each accepted connection's first frame decides its role:
//!   * `AttachHello { auth_token, session_id }`  → **data** conn.
//!     After the AttachAck, the conn switches to raw byte passthrough:
//!     ring replay → live broadcast→stdout, stdin→PTY writer mpsc.
//!   * `Hello { auth_token, client_version }`     → **control** conn.
//!     JSON-RPC request/response loop with concurrent server-pushed
//!     notifications drained from the EventBus.
//!
//! Detection: read the first newline frame, attempt `AttachHello` first
//! (its `session_id` field is required and won't match a `Hello`).

use std::os::unix::fs::PermissionsExt;
use std::panic::AssertUnwindSafe;
use std::str::FromStr;
use std::sync::Arc;

use anyhow::{Context, Result};
use base64::{Engine, engine::general_purpose::STANDARD};
use bytes::Bytes;
use futures_util::{SinkExt, StreamExt};
use roost_core::dto::{
    HostInfo, RevisionEntry, SessionId, SessionState, StatusEntry, WorkspaceEntry,
};
use roost_core::paths;
use roost_core::rpc::{
    self, AddWorkspaceParams, AttachAck, AttachHello, BookmarkParams, CreateSessionParams,
    CreateSessionResult, ForgetWorkspaceParams, Hello, HelloAck, HostInfoResult, IsJjRepoParams,
    IsJjRepoResult, KillSessionParams, Manifest, RenameWorkspaceParams, RepoDirParams, Request,
    ResizeSessionParams, Response, RevisionResult, RpcError, SendInputParams, SessionListResult,
    ShutdownAck, ShutdownDoneEvent, ShutdownMode, ShutdownParams, ShutdownProgressEvent,
    StatusResult, StringResult, WorkspaceDirParams, WorkspaceListResult, WorkspaceResult,
};
use serde::Serialize;
use serde_json::Value;
use tokio::fs;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use tokio::signal::unix::{SignalKind, signal};
use tokio::sync::mpsc;
use tokio_util::codec::{Framed, LinesCodec};
use tracing::{error, info, warn};

use crate::manifest;
use crate::session::{registry::SessionEntry, spawn::spawn_session};
use crate::state::HostState;

const NOTIF_QUEUE_DEPTH: usize = 256;

pub async fn run(state: Arc<HostState>) -> Result<()> {
    let dir = paths::hostd_dir();
    fs::create_dir_all(&dir)
        .await
        .with_context(|| format!("create {}", dir.display()))?;
    let mut perms = fs::metadata(&dir).await?.permissions();
    perms.set_mode(0o700);
    fs::set_permissions(&dir, perms).await?;

    let socket = paths::socket_path();
    let listener = UnixListener::bind(&socket)
        .with_context(|| format!("bind {}", socket.display()))?;
    let mut sock_perms = fs::metadata(&socket).await?.permissions();
    sock_perms.set_mode(0o600);
    fs::set_permissions(&socket, sock_perms).await?;
    info!("listening on {}", socket.display());

    let pid = std::process::id();
    let m = Manifest {
        pid,
        socket: socket.to_string_lossy().into_owned(),
        auth_token: state.auth_token.clone(),
        version: roost_core::HOSTD_VERSION.to_string(),
        started_at_epoch_ms: state.started_at_epoch_ms,
    };
    manifest::write(&m).await?;

    let mut sigterm = signal(SignalKind::terminate())?;
    let mut sigint = signal(SignalKind::interrupt())?;
    let shutdown_notify = state.shutdown.clone();

    loop {
        tokio::select! {
            res = listener.accept() => {
                match res {
                    Ok((stream, _addr)) => {
                        let st = state.clone();
                        tokio::spawn(async move {
                            if let Err(e) = handle_conn(stream, st).await {
                                warn!("connection ended: {e}");
                            }
                        });
                    }
                    Err(e) => {
                        error!("accept failed: {e}");
                        break;
                    }
                }
            }
            _ = sigterm.recv() => {
                info!("SIGTERM → Stop");
                let live = state.sessions.live_session_pids();
                run_stop(state.clone(), live).await; // never returns
                break;
            }
            _ = sigint.recv() => {
                info!("SIGINT → Stop");
                let live = state.sessions.live_session_pids();
                run_stop(state.clone(), live).await; // never returns
                break;
            }
            _ = shutdown_notify.notified() => {
                info!("shutdown notified");
                break;
            }
        }
    }

    info!("accept loop exiting; cleaning manifest + socket");
    manifest::remove().await;
    Ok(())
}

async fn handle_conn(stream: UnixStream, state: Arc<HostState>) -> Result<()> {
    let codec = LinesCodec::new_with_max_length(8 * 1024 * 1024);
    let mut framed = Framed::new(stream, codec);

    let first = framed
        .next()
        .await
        .ok_or_else(|| anyhow::anyhow!("client closed before first frame"))??;

    // Try AttachHello first (its `session_id` field forces that arm only when
    // the field is present and parseable as a UUID).
    if let Ok(att) = serde_json::from_str::<AttachHello>(&first) {
        return handle_data_conn(framed, state, att).await;
    }

    let hello: Hello = match serde_json::from_str(&first) {
        Ok(h) => h,
        Err(e) => {
            let ack = HelloAck {
                ok: false,
                server_version: roost_core::HOSTD_VERSION.into(),
                error: Some(format!("malformed hello: {e}")),
            };
            send_json(&mut framed, &ack).await?;
            return Ok(());
        }
    };
    handle_control_conn(framed, state, hello).await
}

async fn handle_control_conn(
    mut framed: Framed<UnixStream, LinesCodec>,
    state: Arc<HostState>,
    hello: Hello,
) -> Result<()> {
    if hello.auth_token != state.auth_token {
        let ack = HelloAck {
            ok: false,
            server_version: roost_core::HOSTD_VERSION.into(),
            error: Some("bad auth_token".into()),
        };
        send_json(&mut framed, &ack).await?;
        return Ok(());
    }

    let server_major = rpc::major_of(roost_core::HOSTD_VERSION);
    let client_major = rpc::major_of(&hello.client_version);
    if server_major != client_major {
        let ack = HelloAck {
            ok: false,
            server_version: roost_core::HOSTD_VERSION.into(),
            error: Some(format!(
                "version major mismatch: client={} server={}",
                hello.client_version,
                roost_core::HOSTD_VERSION
            )),
        };
        send_json(&mut framed, &ack).await?;
        return Ok(());
    }

    let ack = HelloAck {
        ok: true,
        server_version: roost_core::HOSTD_VERSION.into(),
        error: None,
    };
    send_json(&mut framed, &ack).await?;

    // Concurrent tasks: writer drains the outbound mpsc, reader processes
    // requests + queues responses, event forwarder pushes notifications.
    // Both reader and event forwarder funnel through the writer so frames
    // can't interleave at the byte level.
    let (sink, mut stream) = framed.split();
    let (out_tx, mut out_rx) = mpsc::channel::<String>(NOTIF_QUEUE_DEPTH);

    let mut writer_task = tokio::spawn(async move {
        let mut sink = sink;
        while let Some(line) = out_rx.recv().await {
            if sink.send(line).await.is_err() {
                break;
            }
        }
    });

    let reader_out = out_tx.clone();
    let reader_state = state.clone();
    let reader_task = tokio::spawn(async move {
        while let Some(line) = stream.next().await {
            let line = match line {
                Ok(l) => l,
                Err(_) => break,
            };
            let req: Request = match serde_json::from_str(&line) {
                Ok(r) => r,
                Err(e) => {
                    let resp = error_response(0, rpc::error_codes::PARSE_ERROR, e.to_string());
                    let _ = send_to_writer(&reader_out, &resp).await;
                    continue;
                }
            };
            let resp = dispatch(&reader_state, req).await;
            if send_to_writer(&reader_out, &resp).await.is_err() {
                break;
            }
        }
    });

    let event_out = out_tx.clone();
    let mut events_rx = state.events.subscribe();
    let event_task = tokio::spawn(async move {
        loop {
            match events_rx.recv().await {
                Ok(env) => {
                    let frame = serde_json::json!({
                        "jsonrpc": "2.0",
                        "method": env.method,
                        "params": env.params,
                    });
                    let line = match serde_json::to_string(&frame) {
                        Ok(s) => s,
                        Err(_) => continue,
                    };
                    if event_out.send(line).await.is_err() {
                        break;
                    }
                }
                Err(tokio::sync::broadcast::error::RecvError::Lagged(n)) => {
                    warn!("event subscriber lagged by {n} frames");
                }
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            }
        }
    });

    // When the reader dies (peer closed) we drop the last out_tx so the
    // writer task exits cleanly. The event task gets aborted too — it could
    // otherwise sit on the broadcast forever.
    drop(out_tx);
    let _ = reader_task.await;
    event_task.abort();
    let _ = (&mut writer_task).await;
    Ok(())
}

async fn send_to_writer<T: Serialize>(
    tx: &mpsc::Sender<String>,
    msg: &T,
) -> std::result::Result<(), mpsc::error::SendError<String>> {
    let line = serde_json::to_string(msg).unwrap_or_else(|_| "{}".into());
    tx.send(line).await
}

async fn handle_data_conn(
    mut framed: Framed<UnixStream, LinesCodec>,
    state: Arc<HostState>,
    att: AttachHello,
) -> Result<()> {
    if att.auth_token != state.auth_token {
        let ack = AttachAck {
            ok: false,
            server_version: roost_core::HOSTD_VERSION.into(),
            error: Some("bad auth_token".into()),
            replay_b64: String::new(),
        };
        send_json(&mut framed, &ack).await?;
        return Ok(());
    }

    let attach = state.sessions.with(att.session_id, |entry| {
        let (snap, rx) = entry.subscribe();
        (entry.stdin_tx.clone(), rx, snap)
    });
    let (stdin_tx_opt, mut bcast_rx, replay) = match attach {
        Some(t) => t,
        None => {
            let ack = AttachAck {
                ok: false,
                server_version: roost_core::HOSTD_VERSION.into(),
                error: Some(format!("unknown session {}", att.session_id)),
                replay_b64: String::new(),
            };
            send_json(&mut framed, &ack).await?;
            return Ok(());
        }
    };

    let ack = AttachAck {
        ok: true,
        server_version: roost_core::HOSTD_VERSION.into(),
        error: None,
        replay_b64: STANDARD.encode(&replay),
    };
    send_json(&mut framed, &ack).await?;

    // Switch to raw byte mode: split the underlying UnixStream out of Framed
    // and drop the codec.
    let parts = framed.into_parts();
    let stream = parts.io;
    let (mut read_half, mut write_half) = stream.into_split();

    let sid = att.session_id;

    // Exited session: stdin path is gone, but the ring replay we just sent
    // is the scrollback the user came for. Half-close write so the client
    // sees EOF and don't bother spawning the I/O tasks.
    let Some(stdin_tx) = stdin_tx_opt else {
        let _ = write_half.shutdown().await;
        info!(%sid, "attach to exited session served replay; closing");
        return Ok(());
    };

    let stdin_tx_for_read = stdin_tx.clone();
    let mut read_task = tokio::spawn(async move {
        let mut buf = vec![0u8; 4096];
        loop {
            match read_half.read(&mut buf).await {
                Ok(0) => break,
                Ok(n) => {
                    let chunk = Bytes::copy_from_slice(&buf[..n]);
                    if stdin_tx_for_read.send(chunk).await.is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });

    let mut write_task = tokio::spawn(async move {
        loop {
            match bcast_rx.recv().await {
                Ok(chunk) => {
                    if write_half.write_all(&chunk).await.is_err() {
                        break;
                    }
                }
                // Bytes lost from a raw stream put the VT state machine into
                // an unrecoverable mid-sequence state (CSI/OSC truncation
                // → permanent color/cursor corruption). Disconnect so the
                // attacher reconnects + replays the ring instead of silently
                // continuing on a torn stream.
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => break,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => break,
            }
        }
    });

    // Either side closes → tear the other down. tokio::JoinHandle's Drop
    // doesn't abort, so without an explicit abort the surviving task runs
    // forever (especially the read_task, which would keep entry.stdin_tx
    // pinned and leak the writer/PTY chain).
    tokio::select! {
        _ = &mut read_task  => { write_task.abort(); }
        _ = &mut write_task => { read_task.abort();  }
    }
    let _ = read_task.await;
    let _ = write_task.await;
    if let Some(info) = state.sessions.get_info(att.session_id) {
        if info.state != SessionState::Exited {
            state
                .sessions
                .set_state(att.session_id, SessionState::Detached);
        }
    }
    info!(%sid, "data conn closed");
    Ok(())
}

async fn send_json<T: Serialize>(
    framed: &mut Framed<UnixStream, LinesCodec>,
    msg: &T,
) -> Result<()> {
    let s = serde_json::to_string(msg)?;
    framed.send(s).await?;
    Ok(())
}

async fn dispatch(state: &Arc<HostState>, req: Request) -> Response {
    let id = req.id;
    let method = req.method.clone();
    let params = req.params.unwrap_or(Value::Null);

    // Domain handlers split across sync (jj — runs on blocking pool) and
    // async (sessions — touch tokio channels). Wrap sync ones in
    // catch_unwind so a single bad call can't kill the daemon.
    if is_async_method(&method) {
        let outcome = handle_async_method(state, &method, params).await;
        match outcome {
            Ok(value) => ok_response(id, value),
            Err(err) => Response {
                jsonrpc: "2.0".into(),
                id,
                result: None,
                error: Some(err),
            },
        }
    } else {
        let state_for = state.clone();
        let join = tokio::task::spawn_blocking(move || {
            let result = std::panic::catch_unwind(AssertUnwindSafe(|| {
                handle_sync_method(&state_for, &method, params)
            }));
            match result {
                Ok(r) => r,
                Err(panic) => {
                    let msg = panic_message(&panic);
                    Err(RpcError::panic(format!("handler panicked: {msg}")))
                }
            }
        })
        .await;

        let outcome = match join {
            Ok(r) => r,
            Err(e) => Err(RpcError::internal(format!("join error: {e}"))),
        };

        match outcome {
            Ok(value) => ok_response(id, value),
            Err(err) => Response {
                jsonrpc: "2.0".into(),
                id,
                result: None,
                error: Some(err),
            },
        }
    }
}

fn ok_response(id: u64, value: Value) -> Response {
    Response {
        jsonrpc: "2.0".into(),
        id,
        result: Some(value),
        error: None,
    }
}

fn error_response(id: u64, code: i32, msg: impl Into<String>) -> Response {
    Response {
        jsonrpc: "2.0".into(),
        id,
        result: None,
        error: Some(RpcError {
            code,
            message: msg.into(),
        }),
    }
}

fn panic_message(p: &(dyn std::any::Any + Send)) -> String {
    if let Some(s) = p.downcast_ref::<&str>() {
        (*s).to_string()
    } else if let Some(s) = p.downcast_ref::<String>() {
        s.clone()
    } else {
        "<non-string panic>".to_string()
    }
}

fn is_async_method(method: &str) -> bool {
    use rpc::methods::*;
    matches!(
        method,
        CREATE_SESSION
            | LIST_SESSIONS
            | KILL_SESSION
            | RESIZE_SESSION
            | SEND_INPUT
            | SHUTDOWN
            | LIST_SESSION_HISTORY
    )
}

async fn handle_async_method(
    state: &Arc<HostState>,
    method: &str,
    params: Value,
) -> Result<Value, RpcError> {
    use rpc::methods::*;

    match method {
        CREATE_SESSION => {
            let p: CreateSessionParams = decode(params)?;
            let spec = p.spec.clone();
            let spawned = spawn_session(p.spec, Some(state.events.clone()))
                .map_err(|e| RpcError::domain(e.to_string()))?;
            let id = spawned.id;
            let info = spawned.entry.info.clone();
            state.sessions.insert(spawned.entry);

            // Emit Running state on insert.
            state.events.emit_session_state(rpc::SessionStateEvent {
                session_id: id,
                state: SessionState::Running,
            });

            // Single task: persist the row, THEN await exit, THEN persist
            // the exit. Two independent spawns can race on a fast-exiting
            // child — the UPDATE WHERE id=? matched zero rows because the
            // INSERT hadn't run yet, leaving a permanent 'running' row.
            let exited_rx = spawned.exited_rx;
            let registry = state.sessions.clone();
            let events = state.events.clone();
            let pool = state.db.clone();
            let info_for_task = info.clone();
            tokio::spawn(async move {
                crate::store::insert_session(&pool, &info_for_task, &spec).await;
                let code = exited_rx.await.ok().flatten();
                // set_exit drops stdin_tx + resize_tx, closing the writer
                // + resize channels and letting those blocking tasks (and
                // the PTY master they hold) finally release. The row
                // stays in the registry so list_sessions still surfaces
                // Exited + scrollback.
                registry.set_exit(id, code);
                crate::store::update_session_exit(&pool, id, code).await;
                events.emit_session_state(rpc::SessionStateEvent {
                    session_id: id,
                    state: SessionState::Exited,
                });
                events.emit_session_exited(rpc::SessionExitedEvent {
                    session_id: id,
                    exit_code: code,
                });
            });

            ok(CreateSessionResult { info })
        }
        LIST_SESSION_HISTORY => {
            let history = crate::store::list_session_history(&state.db)
                .await
                .map_err(|e| RpcError::internal(e.to_string()))?;
            ok(SessionListResult { sessions: history })
        }
        LIST_SESSIONS => {
            let sessions = state.sessions.list();
            ok(SessionListResult { sessions })
        }
        KILL_SESSION => {
            let p: KillSessionParams = decode(params)?;
            let pid = state
                .sessions
                .get_info(p.session_id)
                .and_then(|i| i.pid)
                .ok_or_else(|| {
                    RpcError::domain(format!("session {} has no pid", p.session_id))
                })?;
            let signal = if p.signal == 0 { libc::SIGTERM } else { p.signal };
            // SAFETY: kill(pid, sig) is the standard process-signaling API;
            // unsafe wrapping is required because it's a libc binding.
            let rc = unsafe { libc::kill(pid as libc::pid_t, signal) };
            if rc != 0 {
                let err = std::io::Error::last_os_error();
                return Err(RpcError::domain(format!("kill failed: {err}")));
            }
            ok(rpc::Empty::default())
        }
        RESIZE_SESSION => {
            let p: ResizeSessionParams = decode(params)?;
            let sent = state.sessions.with(p.session_id, |entry| {
                entry
                    .resize_tx
                    .as_ref()
                    .map(|tx| tx.send((p.rows, p.cols)).is_ok())
            });
            match sent {
                Some(Some(true)) => ok(rpc::Empty::default()),
                Some(Some(false)) | Some(None) => {
                    Err(RpcError::domain("resize channel closed (session exited?)"))
                }
                None => Err(RpcError::domain(format!("unknown session {}", p.session_id))),
            }
        }
        SHUTDOWN => {
            let p: ShutdownParams = decode(params)?;
            let live = state.sessions.live_session_pids();
            let live_count = live.len() as u32;
            match p.mode {
                ShutdownMode::Release => {
                    // Remove the manifest so the next launch's adopt path
                    // sees "no daemon" and spawns fresh — we keep running
                    // (and can be re-adopted via socket) but we no longer
                    // claim the canonical slot. Sessions stay alive.
                    crate::manifest::remove().await;
                    info!("shutdown(Release): manifest removed; staying up");
                    ok(ShutdownAck { live_sessions: live_count })
                }
                ShutdownMode::Stop => {
                    let state_for_bg = state.clone();
                    tokio::spawn(async move { run_stop(state_for_bg, live).await });
                    ok(ShutdownAck { live_sessions: live_count })
                }
            }
        }
        SEND_INPUT => {
            let p: SendInputParams = decode(params)?;
            let bytes = STANDARD
                .decode(p.data_b64.as_bytes())
                .map_err(|e| RpcError::invalid_params(format!("data_b64: {e}")))?;
            let tx = state
                .sessions
                .with(p.session_id, |entry| entry.stdin_tx.clone());
            let tx = match tx {
                Some(Some(tx)) => tx,
                Some(None) => {
                    return Err(RpcError::domain("session stdin closed (session exited?)"));
                }
                None => {
                    return Err(RpcError::domain(format!("unknown session {}", p.session_id)));
                }
            };
            tx.send(Bytes::from(bytes))
                .await
                .map_err(|_| RpcError::domain("session stdin closed"))?;
            ok(rpc::Empty::default())
        }
        other => Err(RpcError::method_not_found(other)),
    }
}

fn handle_sync_method(state: &HostState, method: &str, params: Value) -> Result<Value, RpcError> {
    use rpc::methods::*;

    match method {
        HOST_INFO => {
            let info = HostInfo {
                version: roost_core::HOSTD_VERSION.to_string(),
                pid: std::process::id(),
                uptime_secs: state.uptime_secs(),
                session_count: state.sessions.count() as u32,
            };
            ok(HostInfoResult { info })
        }
        IS_JJ_REPO => {
            let p: IsJjRepoParams = decode(params)?;
            let v = roost_core::jj::is_jj_repo(&p.dir);
            ok(IsJjRepoResult { is_jj_repo: v })
        }
        JJ_VERSION => {
            let value = roost_core::jj::version().map_err(RpcError::domain)?;
            ok(StringResult { value })
        }
        LIST_WORKSPACES => {
            let p: RepoDirParams = decode(params)?;
            let entries: Vec<WorkspaceEntry> =
                roost_core::jj::list_workspaces(&p.repo_dir).map_err(RpcError::domain)?;
            ok(WorkspaceListResult { entries })
        }
        ADD_WORKSPACE => {
            let p: AddWorkspaceParams = decode(params)?;
            let entry = roost_core::jj::add_workspace(&p.repo_dir, &p.workspace_path, &p.name)
                .map_err(RpcError::domain)?;
            ok(WorkspaceResult { entry })
        }
        FORGET_WORKSPACE => {
            let p: ForgetWorkspaceParams = decode(params)?;
            roost_core::jj::forget_workspace(&p.repo_dir, &p.name).map_err(RpcError::domain)?;
            ok(rpc::Empty::default())
        }
        RENAME_WORKSPACE => {
            let p: RenameWorkspaceParams = decode(params)?;
            roost_core::jj::rename_workspace(&p.workspace_dir, &p.new_name)
                .map_err(RpcError::domain)?;
            ok(rpc::Empty::default())
        }
        UPDATE_STALE => {
            let p: WorkspaceDirParams = decode(params)?;
            roost_core::jj::update_stale(&p.workspace_dir).map_err(RpcError::domain)?;
            ok(rpc::Empty::default())
        }
        WORKSPACE_ROOT => {
            let p: WorkspaceDirParams = decode(params)?;
            let value =
                roost_core::jj::workspace_root(&p.workspace_dir).map_err(RpcError::domain)?;
            ok(StringResult { value })
        }
        CURRENT_REVISION => {
            let p: WorkspaceDirParams = decode(params)?;
            let entry: RevisionEntry =
                roost_core::jj::current_revision(&p.workspace_dir).map_err(RpcError::domain)?;
            ok(RevisionResult { entry })
        }
        WORKSPACE_STATUS => {
            let p: WorkspaceDirParams = decode(params)?;
            let entry: StatusEntry =
                roost_core::jj::status(&p.workspace_dir).map_err(RpcError::domain)?;
            ok(StatusResult { entry })
        }
        BOOKMARK_CREATE => {
            let p: BookmarkParams = decode(params)?;
            roost_core::jj::bookmark_create(&p.workspace_dir, &p.name)
                .map_err(RpcError::domain)?;
            ok(rpc::Empty::default())
        }
        BOOKMARK_FORGET => {
            let p: BookmarkParams = decode(params)?;
            roost_core::jj::bookmark_forget(&p.workspace_dir, &p.name)
                .map_err(RpcError::domain)?;
            ok(rpc::Empty::default())
        }
        other => Err(RpcError::method_not_found(other)),
    }
}

fn ok<T: Serialize>(v: T) -> Result<Value, RpcError> {
    serde_json::to_value(v).map_err(|e| RpcError::internal(e.to_string()))
}

fn decode<T: serde::de::DeserializeOwned>(v: Value) -> Result<T, RpcError> {
    serde_json::from_value(v).map_err(|e| RpcError::invalid_params(e.to_string()))
}

// SessionId FromStr is only used in places that may parse string IDs from
// CLI args later; keep the import live so the rustc warning is suppressed.
#[allow(dead_code)]
fn _force_use_session_id_from_str(s: &str) -> Option<SessionId> {
    SessionId::from_str(s).ok()
}

// Capture for unused-but-conceptually-shared SessionEntry import.
#[allow(dead_code)]
fn _force_use_session_entry(_e: &SessionEntry) {}

const STOP_GRACE: std::time::Duration = std::time::Duration::from_secs(5);
const STOP_KILL_GRACE: std::time::Duration = std::time::Duration::from_secs(1);
const STOP_POLL: std::time::Duration = std::time::Duration::from_millis(100);

async fn run_stop(state: Arc<HostState>, live: Vec<(SessionId, u32)>) {
    let started = std::time::Instant::now();
    let total = live.len();
    info!("shutdown(Stop): SIGTERM {} session(s)", total);

    // Initial progress so the client can render "Stopping N agents…"
    state.events.emit_shutdown_progress(ShutdownProgressEvent {
        remaining_sessions: total as u32,
        elapsed_ms: 0,
        last_session_id: None,
    });

    // Phase 1: SIGTERM all, await with grace.
    for (_id, pid) in &live {
        // SAFETY: standard libc kill; -1 just gets reported as a warn.
        let rc = unsafe { libc::kill(*pid as libc::pid_t, libc::SIGTERM) };
        if rc != 0 {
            warn!(
                "kill SIGTERM pid={pid} failed: {}",
                std::io::Error::last_os_error()
            );
        }
    }

    // Carry the (id, pid) pair through both phases. SIGKILL needs the pid
    // even after the session has transitioned to Detached (data conn
    // closed mid-grace) — at which point live_session_pids() no longer
    // returns it.
    let mut remaining: Vec<(SessionId, u32)> = live.clone();
    let grace_deadline = started + STOP_GRACE;
    while !remaining.is_empty() && std::time::Instant::now() < grace_deadline {
        tokio::time::sleep(STOP_POLL).await;
        prune_progress(&state, &mut remaining, total, started);
    }

    // Phase 2: SIGKILL stragglers, brief grace. Use the original pids;
    // is_done is what tells us a process has actually exited (Detached
    // means agent's still alive but unattached).
    let mut forced = 0u32;
    if !remaining.is_empty() {
        warn!("shutdown(Stop): {} stragglers; SIGKILL", remaining.len());
        for (_id, pid) in &remaining {
            let rc = unsafe { libc::kill(*pid as libc::pid_t, libc::SIGKILL) };
            if rc == 0 {
                forced += 1;
            }
        }
        let kill_deadline = std::time::Instant::now() + STOP_KILL_GRACE;
        while !remaining.is_empty() && std::time::Instant::now() < kill_deadline {
            tokio::time::sleep(STOP_POLL).await;
            prune_progress(&state, &mut remaining, total, started);
        }
    }

    let elapsed_ms = started.elapsed().as_millis() as u64;
    state.events.emit_shutdown_done(ShutdownDoneEvent {
        forced_kills: forced,
        elapsed_ms,
    });

    // Give the broadcast a chance to flush the done event to subscribers
    // before we yank everything. 200ms ≫ tokio worker poll cycle on a busy
    // Mac; reviewer flagged 50ms as borderline under load (event_task →
    // mpsc → writer_task → socket all need to happen within the window).
    tokio::time::sleep(std::time::Duration::from_millis(200)).await;

    info!(
        "shutdown(Stop) complete: forced={} elapsed_ms={} → process::exit(0)",
        forced, elapsed_ms
    );
    crate::manifest::remove().await;
    // The bg task owns the exit. Calling process::exit here (rather than
    // notifying the accept loop and dropping the runtime) avoids a race
    // where runtime Drop aborts this very task before we've flushed the
    // last events to subscribers.
    std::process::exit(0);
}

fn prune_progress(
    state: &HostState,
    remaining: &mut Vec<(SessionId, u32)>,
    total: usize,
    started: std::time::Instant,
) {
    let mut just_done: Vec<SessionId> = Vec::new();
    remaining.retain(|(id, _)| {
        if state.sessions.is_done(*id) {
            just_done.push(*id);
            false
        } else {
            true
        }
    });
    let _ = total; // referenced for future "n of total" UX strings.
    for id in just_done {
        state.events.emit_shutdown_progress(ShutdownProgressEvent {
            remaining_sessions: remaining.len() as u32,
            elapsed_ms: started.elapsed().as_millis() as u64,
            last_session_id: Some(id),
        });
    }
}
