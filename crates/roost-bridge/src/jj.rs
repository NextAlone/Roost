//! Thin wrapper around the `jj` CLI (>= 0.20).
//!
//! We deliberately avoid `jj-lib`: it's flagged unstable upstream and drifts
//! every few releases. The CLI interface is the stable public contract.
//!
//! All functions spawn `jj` with `tokio::process::Command::new("jj")`… no, we
//! use plain `std::process::Command` — the swift-bridge FFI is synchronous and
//! these calls are already measured in tens of milliseconds; a real async
//! runtime comes in §4a of design.md. Errors propagate `stderr` verbatim so
//! the Swift UI can surface them.

use std::path::Path;
use std::process::{Command, Stdio};

#[derive(Debug)]
pub struct WorkspaceEntry {
    pub name: String,
    pub path: String,
    pub change_id: String,
    pub description: String,
    pub is_current: bool,
}

#[derive(Debug)]
pub struct RevisionEntry {
    pub change_id: String,
    pub description: String,
    pub bookmarks: Vec<String>,
}

#[derive(Debug)]
pub struct StatusEntry {
    pub clean: bool,
    pub lines: Vec<String>,
}

/// True if the given path (or an ancestor) is a jj repo. We just invoke
/// `jj status` and trust its exit code. Route through `jj_binary()` so
/// GUI-launched apps still find the binary under a non-login PATH.
///
/// We stdio-null + `--no-pager` to defend against jj's pager launching
/// against an inherited tty (which would hang the app with `less` waiting
/// on RETURN), and suppress the stderr ANSI "no jj repo" message.
pub fn is_jj_repo(dir: &str) -> bool {
    let Ok(bin) = jj_binary() else { return false };
    Command::new(&bin)
        .arg("--no-pager")
        .arg("status")
        .arg("--quiet")
        .current_dir(dir)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// Report the installed jj version string (the first line of `jj --version`).
pub fn version() -> Result<String, String> {
    let out = run(&["--version"], None)?;
    Ok(out.stdout.lines().next().unwrap_or("").trim().to_string())
}

pub fn list_workspaces(repo_dir: &str) -> Result<Vec<WorkspaceEntry>, String> {
    // Template context is `WorkspaceRef` whose only methods are .name() and
    // .target() (a Commit). Path isn't exposed, so we derive it from the
    // `<repo>/.worktrees/<name>` convention (matches addWorkspace); default
    // workspace maps to the repo dir itself.
    // Fields are NUL-separated; jj only recognizes \n \t \r \\ \" \0 escapes.
    let tmpl = concat!(
        r#"name ++ "\0" ++ "#,
        r#"target.change_id().short() ++ "\0" ++ "#,
        r#"target.description().first_line() ++ "\n""#,
    );

    let out = run(&["workspace", "list", "-T", tmpl], Some(repo_dir))?;

    let mut entries = Vec::new();
    for line in out.stdout.lines() {
        let fields: Vec<&str> = line.split('\0').collect();
        if fields.len() < 3 {
            continue;
        }
        let name = fields[0].to_string();
        let path = derive_workspace_path(repo_dir, &name);
        entries.push(WorkspaceEntry {
            name,
            path,
            change_id: fields[1].to_string(),
            description: fields[2].to_string(),
            is_current: false,
        });
    }
    Ok(entries)
}

fn derive_workspace_path(repo_dir: &str, name: &str) -> String {
    if name == "default" {
        return repo_dir.to_string();
    }
    let candidate = format!("{repo_dir}/.worktrees/{name}");
    if Path::new(&candidate).is_dir() {
        candidate
    } else {
        String::new()
    }
}

/// `jj workspace add <path> --name <name>`; returns the new workspace entry.
/// Parent directory is created on demand (jj itself errors if it doesn't
/// exist).
pub fn add_workspace(
    repo_dir: &str,
    workspace_path: &str,
    name: &str,
) -> Result<WorkspaceEntry, String> {
    if let Some(parent) = Path::new(workspace_path).parent() {
        std::fs::create_dir_all(parent)
            .map_err(|e| format!("create parent dir {}: {e}", parent.display()))?;
    }

    run(
        &[
            "workspace",
            "add",
            "--name",
            name,
            workspace_path,
        ],
        Some(repo_dir),
    )?;

    // Locate the fresh entry to return canonical state.
    list_workspaces(repo_dir)?
        .into_iter()
        .find(|w| w.name == name)
        .ok_or_else(|| format!("workspace '{name}' missing from jj workspace list after add"))
}

pub fn forget_workspace(repo_dir: &str, name: &str) -> Result<(), String> {
    run(&["workspace", "forget", name], Some(repo_dir))?;
    Ok(())
}

pub fn rename_workspace(workspace_dir: &str, new_name: &str) -> Result<(), String> {
    // `jj workspace rename` renames the CURRENT workspace, so we run it from
    // inside the target workspace dir.
    run(&["workspace", "rename", new_name], Some(workspace_dir))?;
    Ok(())
}

pub fn update_stale(workspace_dir: &str) -> Result<(), String> {
    run(&["workspace", "update-stale"], Some(workspace_dir))?;
    Ok(())
}

pub fn workspace_root(workspace_dir: &str) -> Result<String, String> {
    let out = run(&["workspace", "root"], Some(workspace_dir))?;
    Ok(out.stdout.trim().to_string())
}

pub fn current_revision(workspace_dir: &str) -> Result<RevisionEntry, String> {
    let tmpl = concat!(
        r#"change_id.short() ++ "\0" ++ "#,
        r#"description.first_line() ++ "\0" ++ "#,
        r#"bookmarks.map(|b| b.name()).join(",")"#,
    );
    let out = run(
        &["log", "-r", "@", "--no-graph", "-T", tmpl, "--limit", "1"],
        Some(workspace_dir),
    )?;
    let line = out.stdout.trim();
    let fields: Vec<&str> = line.split('\0').collect();
    if fields.len() < 3 {
        return Err(format!("unexpected `jj log` output: {line:?}"));
    }
    Ok(RevisionEntry {
        change_id: fields[0].to_string(),
        description: fields[1].to_string(),
        bookmarks: fields[2]
            .split(',')
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string())
            .collect(),
    })
}

pub fn status(workspace_dir: &str) -> Result<StatusEntry, String> {
    let out = run(&["status", "--color=never"], Some(workspace_dir))?;
    let lines: Vec<String> = out.stdout.lines().map(|s| s.to_string()).collect();
    // `jj status` prints "The working copy has no changes." when clean.
    let clean = out.stdout.contains("no changes");
    Ok(StatusEntry { clean, lines })
}

// MARK: - bookmarks

pub fn bookmark_create(workspace_dir: &str, name: &str) -> Result<(), String> {
    run(&["bookmark", "create", "-r", "@", name], Some(workspace_dir))?;
    Ok(())
}

pub fn bookmark_forget(workspace_dir: &str, name: &str) -> Result<(), String> {
    run(&["bookmark", "forget", name], Some(workspace_dir))?;
    Ok(())
}

// MARK: - internals

struct JjOutput {
    stdout: String,
    stderr: String,
}

fn run(args: &[&str], dir: Option<&str>) -> Result<JjOutput, String> {
    let bin = jj_binary()?;
    let mut cmd = Command::new(&bin);
    // `--no-pager` + closed stdin: the FFI runs under a GUI process where
    // an inherited tty would deadlock jj behind `less`. `cmd.output()`
    // already pipes stdout/stderr, but stdin still inherits by default.
    cmd.arg("--no-pager");
    cmd.args(args);
    cmd.stdin(Stdio::null());
    if let Some(d) = dir {
        cmd.current_dir(d);
    }
    let output = cmd
        .output()
        .map_err(|e| format!("failed to spawn {bin} {args:?}: {e}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();

    if !output.status.success() {
        let code = output.status.code().map(|c| c.to_string()).unwrap_or_else(|| "signal".into());
        return Err(format!(
            "jj {args:?} exited {code}\nstdout: {stdout}\nstderr: {stderr}"
        ));
    }
    Ok(JjOutput { stdout, stderr })
}

// Only used for disambiguating touched paths in tests/doc examples.
#[allow(dead_code)]
fn path_component_last(p: &Path) -> String {
    p.file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// Resolve `jj` absolute path. GUI-launched processes inherit launchd's thin
/// PATH, which usually doesn't contain `~/.local/bin` or `/opt/homebrew/bin`;
/// a bare `Command::new("jj")` spawn then fails with ENOENT. Walk the common
/// locations explicitly, with `ROOST_JJ_PATH` as an override.
fn jj_binary() -> Result<String, String> {
    if let Ok(p) = std::env::var("ROOST_JJ_PATH") {
        return Ok(p);
    }

    let home = std::env::var("HOME").unwrap_or_default();
    let user = std::env::var("USER").unwrap_or_default();
    let candidates = [
        format!("{home}/.local/bin/jj"),
        format!("{home}/.nix-profile/bin/jj"),
        format!("/etc/profiles/per-user/{user}/bin/jj"),
        "/opt/homebrew/bin/jj".to_string(),
        "/usr/local/bin/jj".to_string(),
        "/run/current-system/sw/bin/jj".to_string(),
        "/nix/var/nix/profiles/default/bin/jj".to_string(),
        "/usr/bin/jj".to_string(),
    ];

    for candidate in &candidates {
        if Path::new(candidate).is_file() {
            return Ok(candidate.clone());
        }
    }

    // Last-ditch: rely on whatever PATH the process actually has.
    Ok("jj".to_string())
}
