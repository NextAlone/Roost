//! UDS listener + JSON-RPC dispatch.
//!
//! Each connection: hello frame first; on success, a request/response loop
//! using `LinesCodec` for newline-delimited JSON. Dispatch is sync (jj is
//! sync), wrapped in `tokio::task::spawn_blocking` + `catch_unwind` so a
//! panic in one handler doesn't take the daemon down.

use std::os::unix::fs::PermissionsExt;
use std::panic::AssertUnwindSafe;
use std::sync::Arc;

use anyhow::{Context, Result};
use futures_util::{SinkExt, StreamExt};
use roost_core::dto::{HostInfo, RevisionEntry, StatusEntry, WorkspaceEntry};
use roost_core::paths;
use roost_core::rpc::{
    self, AddWorkspaceParams, BookmarkParams, DirParams, ForgetWorkspaceParams, Hello, HelloAck,
    HostInfoResult, IsJjRepoParams, IsJjRepoResult, Manifest, RenameWorkspaceParams, RepoDirParams,
    Request, Response, RevisionResult, RpcError, StatusResult, StringResult, WorkspaceDirParams,
    WorkspaceListResult, WorkspaceResult,
};
use serde::Serialize;
use serde_json::Value;
use tokio::fs;
use tokio::net::{UnixListener, UnixStream};
use tokio::signal::unix::{SignalKind, signal};
use tokio_util::codec::{Framed, LinesCodec};
use tracing::{error, info, warn};

use crate::manifest;
use crate::state::HostState;

pub async fn run(state: Arc<HostState>) -> Result<()> {
    // Bind UDS first so failure surfaces before we touch the manifest.
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

    // Now manifest — atomic 0600 write.
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
            _ = sigterm.recv() => { info!("SIGTERM"); break; }
            _ = sigint.recv()  => { info!("SIGINT"); break; }
        }
    }

    info!("shutting down; cleaning manifest + socket");
    manifest::remove().await;
    Ok(())
}

async fn handle_conn(stream: UnixStream, state: Arc<HostState>) -> Result<()> {
    let codec = LinesCodec::new_with_max_length(8 * 1024 * 1024);
    let mut framed = Framed::new(stream, codec);

    // ---- handshake ----
    let first = framed
        .next()
        .await
        .ok_or_else(|| anyhow::anyhow!("client closed before hello"))??;

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

    // ---- request/response loop ----
    while let Some(line) = framed.next().await {
        let line = line?;
        let req: Request = match serde_json::from_str(&line) {
            Ok(r) => r,
            Err(e) => {
                let resp = Response {
                    jsonrpc: "2.0".into(),
                    id: 0,
                    result: None,
                    error: Some(RpcError {
                        code: rpc::error_codes::PARSE_ERROR,
                        message: format!("parse error: {e}"),
                    }),
                };
                send_json(&mut framed, &resp).await?;
                continue;
            }
        };

        let resp = dispatch(&state, req).await;
        send_json(&mut framed, &resp).await?;
    }

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

    // Domain handlers are sync (jj is sync). Run on blocking pool and wrap in
    // catch_unwind so a single bad call can't kill the daemon.
    let state_for = state.clone();
    let join = tokio::task::spawn_blocking(move || {
        let result = std::panic::catch_unwind(AssertUnwindSafe(|| {
            handle_method(&state_for, &method, params)
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
        Ok(value) => Response {
            jsonrpc: "2.0".into(),
            id,
            result: Some(value),
            error: None,
        },
        Err(err) => Response {
            jsonrpc: "2.0".into(),
            id,
            result: None,
            error: Some(err),
        },
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

fn handle_method(state: &HostState, method: &str, params: Value) -> Result<Value, RpcError> {
    use rpc::methods::*;

    match method {
        HOST_INFO => {
            let info = HostInfo {
                version: roost_core::HOSTD_VERSION.to_string(),
                pid: std::process::id(),
                uptime_secs: state.uptime_secs(),
                session_count: 0,
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

#[allow(unused_imports)]
use DirParams as _;
