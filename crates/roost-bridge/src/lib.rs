//! swift-bridge facade. NO domain logic — every call is one of:
//!   - direct delegation to `roost_core::session::*` (PTY-local, no daemon hop)
//!   - delegation to `roost_client::Client::*` over UDS to roost-hostd
//!
//! The exported FFI surface is unchanged from M5; the Swift app keeps calling
//! `RoostBridge.*` exactly as before.

mod hooks;

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

    extern "Rust" {
        fn roost_greet(name: &str) -> String;
        fn roost_bridge_version() -> String;
        fn roost_prepare_session(agent: &str) -> SessionSpec;
        fn roost_prepare_session_in(agent: &str, working_directory: &str) -> SessionSpec;

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
// Per-call connect: each FFI invocation opens a fresh UnixStream, does the
// hello handshake, makes one request, and drops. Avoids tokio inside FFI and
// removes any global Client state — Swift can call from any thread without
// us caring.

fn client() -> Client {
    Client::new()
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

// MARK: - hooks

fn roost_run_setup_hooks(project_root: String, workspace_dir: String) -> Result<String, String> {
    let results = hooks::run_setup(
        std::path::Path::new(&project_root),
        std::path::Path::new(&workspace_dir),
    )?;
    Ok(hooks::serialize(&results))
}

fn roost_run_teardown_hooks(project_root: String, workspace_dir: String) -> Result<String, String> {
    let results = hooks::run_teardown(
        std::path::Path::new(&project_root),
        std::path::Path::new(&workspace_dir),
    )?;
    Ok(hooks::serialize(&results))
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
