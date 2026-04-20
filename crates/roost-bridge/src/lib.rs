//! swift-bridge facade. NO domain logic — every call is one of:
//!   - direct delegation to `roost_core::session::*` (PTY-local, no daemon hop)
//!   - delegation to `roost_client::Client::*` over UDS to roost-hostd
//!
//! The exported FFI surface is unchanged from M5; the Swift app keeps calling
//! `RoostBridge.*` exactly as before.

mod hooks;

use std::sync::Arc;

use roost_client::{Client, ClientError};

#[swift_bridge::bridge]
mod ffi {
    // MARK: - Sessions

    #[swift_bridge(swift_repr = "struct")]
    struct SessionSpec {
        command: String,
        working_directory: String,
        agent_kind: String,
    }

    // MARK: - jj workspace

    #[swift_bridge(swift_repr = "struct")]
    struct WorkspaceEntry {
        name: String,
        path: String,
        change_id: String,
        description: String,
        is_current: bool,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct RevisionEntry {
        change_id: String,
        description: String,
        bookmarks_csv: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct StatusEntry {
        clean: bool,
        text: String,
    }

    // MARK: - Hostd status (M8)

    #[swift_bridge(swift_repr = "struct")]
    struct HostdStatus {
        pid: u32,
        version: String,
        uptime_secs: u64,
        session_count: u32,
        manifest_path: String,
        socket_path: String,
    }

    // MARK: - Session handle (M7)

    #[swift_bridge(swift_repr = "struct")]
    struct SessionHandle {
        /// Stringified UUID. Pass back through `roost_session_kill` etc.
        session_id: String,
        /// Absolute path to the `roost-attach` binary the app should spawn
        /// as the libghostty surface child.
        attach_binary_path: String,
        /// Hostd UDS path; injected to the relay child as
        /// `ROOST_HOSTD_SOCKET` env var.
        socket: String,
        /// Hostd auth token; injected as `ROOST_AUTH_TOKEN`.
        auth_token: String,
    }

    extern "Rust" {
        fn roost_greet(name: &str) -> String;
        fn roost_bridge_version() -> String;
        fn roost_prepare_session(agent: &str) -> SessionSpec;
        fn roost_prepare_session_in(agent: &str, working_directory: &str) -> SessionSpec;

        // M7 session lifecycle (PTY now lives in hostd).
        fn roost_session_create(
            agent_kind: String,
            working_directory: String,
            rows: u16,
            cols: u16,
        ) -> Result<SessionHandle, String>;
        fn roost_session_kill(session_id: String, signal: i32) -> Result<(), String>;
        fn roost_session_resize(
            session_id: String,
            rows: u16,
            cols: u16,
        ) -> Result<(), String>;
        fn roost_attach_binary_path() -> Result<String, String>;

        // M8 lifecycle. mode = "release" | "stop"; wait_dead polls the
        // manifest + socket and returns true if hostd is gone in time.
        fn roost_hostd_status() -> Result<HostdStatus, String>;
        fn roost_hostd_shutdown(mode: String) -> Result<u32, String>;
        fn roost_hostd_wait_dead(timeout_ms: u64) -> bool;
        // Restore-on-launch surfaces. Live sessions = hostd's in-memory
        // registry (ready to attach). History = SQLite, includes
        // ExitedLost rows from prior crashes. Both go via the same
        // \n + \u{1f} flat encoding the workspace list uses, because
        // swift-bridge 0.1.59 doesn't ship Vec<SharedStruct>.
        fn roost_list_live_sessions_serialized() -> Result<String, String>;
        fn roost_list_session_history_serialized() -> Result<String, String>;

        fn roost_is_jj_repo(dir: &str) -> bool;
        fn roost_jj_version() -> Result<String, String>;
        fn roost_list_workspaces_serialized(repo_dir: String) -> Result<String, String>;
        fn roost_add_workspace(
            repo_dir: String,
            workspace_path: String,
            name: String,
        ) -> Result<WorkspaceEntry, String>;
        fn roost_forget_workspace(repo_dir: String, name: String) -> Result<(), String>;
        fn roost_rename_workspace(workspace_dir: String, new_name: String) -> Result<(), String>;
        fn roost_update_stale(workspace_dir: String) -> Result<(), String>;
        fn roost_workspace_root(workspace_dir: String) -> Result<String, String>;
        fn roost_current_revision(workspace_dir: String) -> Result<RevisionEntry, String>;
        fn roost_workspace_status(workspace_dir: String) -> Result<StatusEntry, String>;
        fn roost_bookmark_create(workspace_dir: String, name: String) -> Result<(), String>;
        fn roost_bookmark_forget(workspace_dir: String, name: String) -> Result<(), String>;

        // .roost/config.json hooks (M5). Returns serialized step results; see
        // `hooks::serialize` for the row format. `Err` only for malformed
        // config JSON / IO problems; per-step command failures show up as a
        // nonzero `exit_code` inside the serialized rows.
        fn roost_run_setup_hooks(
            project_root: String,
            workspace_dir: String,
        ) -> Result<String, String>;
        fn roost_run_teardown_hooks(
            project_root: String,
            workspace_dir: String,
        ) -> Result<String, String>;
    }
}

// MARK: - Smoke

fn roost_greet(name: &str) -> String {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        "Hello from Rust 👋".to_string()
    } else {
        format!("Hello, {trimmed}, from Rust 👋")
    }
}

fn roost_bridge_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

// MARK: - Sessions (local; no daemon hop in M6 — PTY moves in M7)

fn roost_prepare_session(agent: &str) -> ffi::SessionSpec {
    spec_to_ffi(roost_core::session::prepare_default(agent))
}

fn roost_prepare_session_in(agent: &str, working_directory: &str) -> ffi::SessionSpec {
    spec_to_ffi(roost_core::session::prepare(agent, working_directory))
}

fn spec_to_ffi(s: roost_core::dto::SessionSpec) -> ffi::SessionSpec {
    ffi::SessionSpec {
        command: s.command,
        working_directory: s.working_directory,
        agent_kind: s.agent_kind,
    }
}

// MARK: - jj wrappers (delegate to roost-hostd over UDS)
//
// Process-wide singleton `Client` holds a long-lived `Connection` that
// demuxes responses by id and ferries server-pushed events to the (M7-P3+)
// event consumers. The connection is opened lazily on first call and
// reconnects (with hostd respawn if needed) after a `Disconnected`.

fn client() -> Arc<Client> {
    Client::shared()
}

fn roost_is_jj_repo(dir: &str) -> bool {
    client().is_jj_repo(dir).unwrap_or(false)
}

fn roost_jj_version() -> Result<String, String> {
    client().jj_version().map_err(stringify)
}

fn roost_list_workspaces_serialized(repo_dir: String) -> Result<String, String> {
    let entries = client().list_workspaces(&repo_dir).map_err(stringify)?;
    let mut out = String::new();
    for e in entries {
        // Record: name␟path␟change_id␟description␟is_current — same wire
        // format the Swift side already parses.
        out.push_str(&e.name);
        out.push('\u{1f}');
        out.push_str(&e.path);
        out.push('\u{1f}');
        out.push_str(&e.change_id);
        out.push('\u{1f}');
        out.push_str(&e.description);
        out.push('\u{1f}');
        out.push_str(if e.is_current { "1" } else { "0" });
        out.push('\n');
    }
    Ok(out)
}

fn roost_add_workspace(
    repo_dir: String,
    workspace_path: String,
    name: String,
) -> Result<ffi::WorkspaceEntry, String> {
    client()
        .add_workspace(&repo_dir, &workspace_path, &name)
        .map(workspace_to_ffi)
        .map_err(stringify)
}

fn roost_forget_workspace(repo_dir: String, name: String) -> Result<(), String> {
    client()
        .forget_workspace(&repo_dir, &name)
        .map_err(stringify)
}

fn roost_rename_workspace(workspace_dir: String, new_name: String) -> Result<(), String> {
    client()
        .rename_workspace(&workspace_dir, &new_name)
        .map_err(stringify)
}

fn roost_update_stale(workspace_dir: String) -> Result<(), String> {
    client().update_stale(&workspace_dir).map_err(stringify)
}

fn roost_workspace_root(workspace_dir: String) -> Result<String, String> {
    client()
        .workspace_root(&workspace_dir)
        .map_err(stringify)
}

fn roost_current_revision(workspace_dir: String) -> Result<ffi::RevisionEntry, String> {
    client()
        .current_revision(&workspace_dir)
        .map(revision_to_ffi)
        .map_err(stringify)
}

fn roost_workspace_status(workspace_dir: String) -> Result<ffi::StatusEntry, String> {
    client()
        .workspace_status(&workspace_dir)
        .map(status_to_ffi)
        .map_err(stringify)
}

fn roost_bookmark_create(workspace_dir: String, name: String) -> Result<(), String> {
    client()
        .bookmark_create(&workspace_dir, &name)
        .map_err(stringify)
}

fn roost_bookmark_forget(workspace_dir: String, name: String) -> Result<(), String> {
    client()
        .bookmark_forget(&workspace_dir, &name)
        .map_err(stringify)
}

// MARK: - Session lifecycle (M7)

fn roost_session_create(
    agent_kind: String,
    working_directory: String,
    rows: u16,
    cols: u16,
) -> Result<ffi::SessionHandle, String> {
    // Domain logic stays in core::session::prepare so M9 CLI sees the same
    // PATH-resolution behaviour.
    let prepared = roost_core::session::prepare(&agent_kind, &working_directory);
    let spec = roost_client::AgentSpec {
        command: prepared.command,
        working_directory: prepared.working_directory,
        agent_kind: prepared.agent_kind,
        rows,
        cols,
        env: Default::default(),
    };

    let info = client().create_session(spec).map_err(stringify)?;
    let manifest = roost_client::ensure_hostd().map_err(stringify)?;
    let attach = locate_attach_binary().ok_or_else(|| {
        "roost-attach binary not found (set ROOST_ATTACH_PATH or bundle into Resources)"
            .to_string()
    })?;

    Ok(ffi::SessionHandle {
        session_id: info.id.to_string(),
        attach_binary_path: attach,
        socket: manifest.socket,
        auth_token: manifest.auth_token,
    })
}

fn roost_session_kill(session_id: String, signal: i32) -> Result<(), String> {
    let sid = parse_sid(&session_id)?;
    client().kill_session(sid, signal).map_err(stringify)
}

fn roost_session_resize(session_id: String, rows: u16, cols: u16) -> Result<(), String> {
    let sid = parse_sid(&session_id)?;
    client().resize_session(sid, rows, cols).map_err(stringify)
}

fn roost_attach_binary_path() -> Result<String, String> {
    locate_attach_binary().ok_or_else(|| "roost-attach binary not found".to_string())
}

// MARK: - Hostd lifecycle (M8)

fn roost_hostd_status() -> Result<ffi::HostdStatus, String> {
    let info = client().host_info().map_err(stringify)?;
    let manifest = roost_client::roost_core::paths::manifest_path();
    let socket = roost_client::roost_core::paths::socket_path();
    Ok(ffi::HostdStatus {
        pid: info.pid,
        version: info.version,
        uptime_secs: info.uptime_secs,
        session_count: info.session_count,
        manifest_path: manifest.to_string_lossy().into_owned(),
        socket_path: socket.to_string_lossy().into_owned(),
    })
}

fn roost_hostd_shutdown(mode: String) -> Result<u32, String> {
    use roost_client::roost_core::rpc::ShutdownMode;
    let mode = match mode.as_str() {
        "release" => ShutdownMode::Release,
        "stop" => ShutdownMode::Stop,
        other => return Err(format!("unknown shutdown mode {other:?}")),
    };
    let ack = client().shutdown(mode).map_err(stringify)?;
    Ok(ack.live_sessions)
}

fn roost_list_live_sessions_serialized() -> Result<String, String> {
    use roost_client::roost_core::dto::SessionState;
    let sessions = client().list_sessions().map_err(stringify)?;
    let manifest = roost_client::ensure_hostd().map_err(stringify)?;
    let attach = locate_attach_binary().ok_or_else(|| {
        "roost-attach binary not found (set ROOST_ATTACH_PATH or bundle into Resources)"
            .to_string()
    })?;
    let mut out = String::new();
    for info in sessions {
        if info.state != SessionState::Running {
            continue;
        }
        // Record: session_id␟attach_binary_path␟socket␟auth_token␟agent_kind␟working_directory.
        out.push_str(&info.id.to_string());
        out.push('\u{1f}');
        out.push_str(&attach);
        out.push('\u{1f}');
        out.push_str(&manifest.socket);
        out.push('\u{1f}');
        out.push_str(&manifest.auth_token);
        out.push('\u{1f}');
        out.push_str(&info.agent_kind);
        out.push('\u{1f}');
        out.push_str(&info.working_directory);
        out.push('\n');
    }
    Ok(out)
}

fn roost_list_session_history_serialized() -> Result<String, String> {
    let history = client().list_session_history().map_err(stringify)?;
    let mut out = String::new();
    for h in history {
        // Record: id␟agent_kind␟working_directory␟state␟exit_code␟created_at_epoch_ms.
        // Mirrors the row format roost_list_workspaces_serialized uses.
        out.push_str(&h.id.to_string());
        out.push('\u{1f}');
        out.push_str(&h.agent_kind);
        out.push('\u{1f}');
        out.push_str(&h.working_directory);
        out.push('\u{1f}');
        out.push_str(h.state.as_str());
        out.push('\u{1f}');
        if let Some(c) = h.exit_code {
            out.push_str(&c.to_string());
        }
        out.push('\u{1f}');
        out.push_str(&h.created_at_epoch_ms.to_string());
        out.push('\n');
    }
    Ok(out)
}

fn roost_hostd_wait_dead(timeout_ms: u64) -> bool {
    use std::os::unix::net::UnixStream;
    use std::time::{Duration, Instant};
    let socket = roost_client::roost_core::paths::socket_path();
    let manifest = roost_client::roost_core::paths::manifest_path();
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    while Instant::now() < deadline {
        if !manifest.exists() && UnixStream::connect(&socket).is_err() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    false
}

fn parse_sid(s: &str) -> Result<roost_client::SessionId, String> {
    s.parse::<roost_client::SessionId>()
        .map_err(|e| format!("invalid session id {s:?}: {e}"))
}

/// Mirror of roost-client's hostd lookup, for the `roost-attach` sibling.
/// Order: $ROOST_ATTACH_PATH > Bundle Resources > target/{debug,release}
/// > $PATH.
fn locate_attach_binary() -> Option<String> {
    use std::path::{Path, PathBuf};

    if let Ok(p) = std::env::var("ROOST_ATTACH_PATH") {
        let path = PathBuf::from(p);
        if path.is_file() {
            return Some(path.to_string_lossy().into_owned());
        }
    }

    if let Ok(exe) = std::env::current_exe() {
        if let Some(macos_dir) = exe.parent() {
            // Sibling in Contents/MacOS/ — production layout (M8 P4).
            let beside = macos_dir.join("roost-attach");
            if beside.is_file() {
                return Some(beside.to_string_lossy().into_owned());
            }
            // Helpers/ + Resources/ — historical layouts; keep as fallbacks
            // so an old DerivedData build still launches.
            if let Some(contents) = macos_dir.parent() {
                for sub in &["Helpers", "Resources"] {
                    let candidate = contents.join(sub).join("roost-attach");
                    if candidate.is_file() {
                        return Some(candidate.to_string_lossy().into_owned());
                    }
                }
            }
        }
    }

    let mut cur: PathBuf = std::env::current_dir().ok()?;
    for _ in 0..6 {
        for profile in &["debug", "release"] {
            let candidate = cur.join("target").join(profile).join("roost-attach");
            if candidate.is_file() {
                return Some(candidate.to_string_lossy().into_owned());
            }
        }
        if !cur.pop() {
            break;
        }
    }

    if let Ok(path_var) = std::env::var("PATH") {
        for dir in path_var.split(':') {
            let candidate = Path::new(dir).join("roost-attach");
            if candidate.is_file() {
                return Some(candidate.to_string_lossy().into_owned());
            }
        }
    }
    None
}

// MARK: - conversions

fn workspace_to_ffi(e: roost_core::dto::WorkspaceEntry) -> ffi::WorkspaceEntry {
    ffi::WorkspaceEntry {
        name: e.name,
        path: e.path,
        change_id: e.change_id,
        description: e.description,
        is_current: e.is_current,
    }
}

fn revision_to_ffi(e: roost_core::dto::RevisionEntry) -> ffi::RevisionEntry {
    ffi::RevisionEntry {
        change_id: e.change_id,
        description: e.description,
        bookmarks_csv: e.bookmarks.join(","),
    }
}

fn status_to_ffi(e: roost_core::dto::StatusEntry) -> ffi::StatusEntry {
    ffi::StatusEntry {
        clean: e.clean,
        text: e.lines.join("\n"),
    }
}

fn stringify(err: ClientError) -> String {
    err.to_string()
}
