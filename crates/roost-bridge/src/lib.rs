//! Swift-facing bridge for Roost's Rust core.
//!
//! M0.x: `roost_greet` / `roost_bridge_version` / `roost_prepare_session`.
//! M2:   jj workspace / bookmark / status helpers via `jj` CLI.

mod jj;

#[swift_bridge::bridge]
mod ffi {
    // MARK: - Sessions

    #[swift_bridge(swift_repr = "struct")]
    struct SessionSpec {
        /// Shell-style command string (ghostty parses this itself).
        /// Empty => ghostty starts the user's login shell.
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
        /// Comma-separated bookmark names (empty string = none). Avoids the
        /// `Vec<String>` inside a shared struct which swift-bridge's codegen
        /// handles unevenly across versions.
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

        // jj wrappers (M2). Note: using owned `String` args instead of `&str`
        // on Result-returning fns, because swift-bridge 0.1.59 emits broken
        // Swift around `toRustStr` when the inner closure throws.
        fn roost_is_jj_repo(dir: &str) -> bool;
        fn roost_jj_version() -> Result<String, String>;
        // `\n`-delimited records, `\u{1f}`-delimited fields:
        // name␟path␟change_id␟description␟is_current(0|1).
        // swift-bridge can't yet ship Vec<SharedStruct> across FFI, so we
        // marshal to a string and split on the Swift side.
        fn roost_list_workspaces_serialized(repo_dir: String) -> Result<String, String>;
        fn roost_add_workspace(
            repo_dir: String,
            workspace_path: String,
            name: String,
        ) -> Result<WorkspaceEntry, String>;
        fn roost_forget_workspace(repo_dir: String, name: String) -> Result<(), String>;
        fn roost_rename_workspace(
            workspace_dir: String,
            new_name: String,
        ) -> Result<(), String>;
        fn roost_update_stale(workspace_dir: String) -> Result<(), String>;
        fn roost_workspace_root(workspace_dir: String) -> Result<String, String>;
        fn roost_current_revision(workspace_dir: String) -> Result<RevisionEntry, String>;
        fn roost_workspace_status(workspace_dir: String) -> Result<StatusEntry, String>;
        fn roost_bookmark_create(workspace_dir: String, name: String) -> Result<(), String>;
        fn roost_bookmark_forget(workspace_dir: String, name: String) -> Result<(), String>;
    }
}

// MARK: - Smoke tests

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

// MARK: - Sessions

fn roost_prepare_session(agent: &str) -> ffi::SessionSpec {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/".to_string());
    roost_prepare_session_in(agent, &home)
}

fn roost_prepare_session_in(agent: &str, working_directory: &str) -> ffi::SessionSpec {
    let agent_norm = agent.trim().to_lowercase();

    // Always wrap through the user's login shell so the agent inherits their
    // PATH / rc exports (jj, node, etc.). GUI-launched apps only get launchd's
    // thin PATH, so a direct exec leaves agents unable to find their siblings.
    //
    // `$SHELL` is typically set for GUI apps too (launchd populates it from
    // the user record); fall back to `/bin/zsh` which is the macOS default.
    // Using "-l -c" as the universal login-invocation form — bash, zsh, and
    // fish all accept it.
    let command = match agent_norm.as_str() {
        "" | "shell" | "bash" | "zsh" | "fish" => String::new(),
        name => {
            let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".to_string());
            format!("{shell} -l -c {name}")
        }
    };

    ffi::SessionSpec {
        command,
        working_directory: working_directory.to_string(),
        agent_kind: agent_norm,
    }
}

// MARK: - jj bindings (thin delegate to jj::* with FFI struct conversion)

fn roost_is_jj_repo(dir: &str) -> bool {
    jj::is_jj_repo(dir)
}

fn roost_jj_version() -> Result<String, String> {
    jj::version()
}

fn roost_list_workspaces_serialized(repo_dir: String) -> Result<String, String> {
    let entries = jj::list_workspaces(&repo_dir)?;
    let mut out = String::new();
    for e in entries {
        // Record: name␟path␟change_id␟description␟is_current
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
    jj::add_workspace(&repo_dir, &workspace_path, &name).map(Into::into)
}

fn roost_forget_workspace(repo_dir: String, name: String) -> Result<(), String> {
    jj::forget_workspace(&repo_dir, &name)
}

fn roost_rename_workspace(workspace_dir: String, new_name: String) -> Result<(), String> {
    jj::rename_workspace(&workspace_dir, &new_name)
}

fn roost_update_stale(workspace_dir: String) -> Result<(), String> {
    jj::update_stale(&workspace_dir)
}

fn roost_workspace_root(workspace_dir: String) -> Result<String, String> {
    jj::workspace_root(&workspace_dir)
}

fn roost_current_revision(workspace_dir: String) -> Result<ffi::RevisionEntry, String> {
    jj::current_revision(&workspace_dir).map(Into::into)
}

fn roost_workspace_status(workspace_dir: String) -> Result<ffi::StatusEntry, String> {
    jj::status(&workspace_dir).map(Into::into)
}

fn roost_bookmark_create(workspace_dir: String, name: String) -> Result<(), String> {
    jj::bookmark_create(&workspace_dir, &name)
}

fn roost_bookmark_forget(workspace_dir: String, name: String) -> Result<(), String> {
    jj::bookmark_forget(&workspace_dir, &name)
}

// MARK: - domain → FFI conversions

impl From<jj::WorkspaceEntry> for ffi::WorkspaceEntry {
    fn from(e: jj::WorkspaceEntry) -> Self {
        ffi::WorkspaceEntry {
            name: e.name,
            path: e.path,
            change_id: e.change_id,
            description: e.description,
            is_current: e.is_current,
        }
    }
}

impl From<jj::RevisionEntry> for ffi::RevisionEntry {
    fn from(e: jj::RevisionEntry) -> Self {
        ffi::RevisionEntry {
            change_id: e.change_id,
            description: e.description,
            bookmarks_csv: e.bookmarks.join(","),
        }
    }
}

impl From<jj::StatusEntry> for ffi::StatusEntry {
    fn from(e: jj::StatusEntry) -> Self {
        ffi::StatusEntry {
            clean: e.clean,
            text: e.lines.join("\n"),
        }
    }
}
