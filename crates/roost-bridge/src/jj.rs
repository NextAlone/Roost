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
    Ok(parse_workspace_lines(&out.stdout, repo_dir))
}

/// Parse the NUL-separated template output of `jj workspace list`.
/// Exposed for unit tests so we don't need a jj binary to cover format
/// drift.
pub(crate) fn parse_workspace_lines(stdout: &str, repo_dir: &str) -> Vec<WorkspaceEntry> {
    let mut entries = Vec::new();
    for line in stdout.lines() {
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
    entries
}

pub(crate) fn derive_workspace_path(repo_dir: &str, name: &str) -> String {
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
    parse_revision(&out.stdout)
}

/// Parse the NUL-separated template output of `jj log -r @`.
pub(crate) fn parse_revision(stdout: &str) -> Result<RevisionEntry, String> {
    let line = stdout.trim();
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
    Ok(parse_status(&out.stdout))
}

/// Build `StatusEntry` from a raw `jj status --color=never` stdout.
pub(crate) fn parse_status(stdout: &str) -> StatusEntry {
    let lines: Vec<String> = stdout.lines().map(|s| s.to_string()).collect();
    // `jj status` prints "The working copy has no changes." when clean.
    let clean = stdout.contains("no changes");
    StatusEntry { clean, lines }
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

// MARK: - tests
//
// The pure parse helpers above (`parse_workspace_lines`, `parse_revision`,
// `parse_status`, `derive_workspace_path`) intentionally don't spawn jj so
// we can cover format-drift regressions cheaply. Integration tests that
// actually invoke a jj binary live in `tests/` (M6+).

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn tempdir(label: &str) -> std::path::PathBuf {
        use std::time::{SystemTime, UNIX_EPOCH};
        let n = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        let mut p = std::env::temp_dir();
        p.push(format!("roost-jj-{label}-{}-{n:x}", std::process::id()));
        fs::create_dir_all(&p).unwrap();
        p
    }

    // --- derive_workspace_path -------------------------------------------

    #[test]
    fn default_workspace_maps_to_repo_root() {
        assert_eq!(
            derive_workspace_path("/some/repo", "default"),
            "/some/repo"
        );
    }

    #[test]
    fn named_workspace_uses_worktrees_convention_when_exists() {
        let repo = tempdir("derive-exists");
        let ws = repo.join(".worktrees").join("foo");
        fs::create_dir_all(&ws).unwrap();
        assert_eq!(
            derive_workspace_path(repo.to_str().unwrap(), "foo"),
            ws.to_str().unwrap()
        );
    }

    #[test]
    fn named_workspace_returns_empty_when_missing() {
        let repo = tempdir("derive-missing");
        // No .worktrees/foo created.
        assert_eq!(
            derive_workspace_path(repo.to_str().unwrap(), "foo"),
            ""
        );
    }

    #[test]
    fn derive_does_not_treat_file_as_dir() {
        let repo = tempdir("derive-file");
        let fake = repo.join(".worktrees").join("bar");
        fs::create_dir_all(fake.parent().unwrap()).unwrap();
        fs::write(&fake, "").unwrap(); // regular file, not a dir
        assert_eq!(
            derive_workspace_path(repo.to_str().unwrap(), "bar"),
            ""
        );
    }

    // --- parse_workspace_lines -------------------------------------------

    #[test]
    fn parse_workspace_lines_basic() {
        let stdout = "default\0abc1234\0initial commit\nws-a\0def5678\0feat: login\n";
        let entries = parse_workspace_lines(stdout, "/repo");
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].name, "default");
        assert_eq!(entries[0].path, "/repo");
        assert_eq!(entries[0].change_id, "abc1234");
        assert_eq!(entries[0].description, "initial commit");
        assert_eq!(entries[1].name, "ws-a");
        // ws-a has no directory on disk → path empty (caller can still display).
        assert_eq!(entries[1].path, "");
    }

    #[test]
    fn parse_workspace_lines_skips_malformed() {
        let stdout = "good\0id\0desc\njust-a-name\n\0\0\n";
        let entries = parse_workspace_lines(stdout, "/repo");
        // Only the first and third (empty-empty-empty) lines have >=3 fields.
        // The second ("just-a-name") is a single field → skipped.
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].name, "good");
        assert_eq!(entries[1].name, ""); // all-empty row still parseable
    }

    #[test]
    fn parse_workspace_lines_empty_input() {
        assert!(parse_workspace_lines("", "/repo").is_empty());
        assert!(parse_workspace_lines("\n\n", "/repo").is_empty());
    }

    #[test]
    fn parse_workspace_lines_extra_fields_are_ignored() {
        // Future-proofing: if the template gains a 4th field we shouldn't
        // reject the row, just drop the tail.
        let stdout = "default\0abc\0desc\0extra\0stuff\n";
        let entries = parse_workspace_lines(stdout, "/repo");
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].change_id, "abc");
        assert_eq!(entries[0].description, "desc");
    }

    // --- parse_revision --------------------------------------------------

    #[test]
    fn parse_revision_with_bookmarks() {
        let rev = parse_revision("xyz9876\0fix: race in foo\0main,feat-login").unwrap();
        assert_eq!(rev.change_id, "xyz9876");
        assert_eq!(rev.description, "fix: race in foo");
        assert_eq!(rev.bookmarks, vec!["main", "feat-login"]);
    }

    #[test]
    fn parse_revision_no_bookmarks() {
        let rev = parse_revision("abc1234\0wip\0").unwrap();
        assert!(rev.bookmarks.is_empty());
    }

    #[test]
    fn parse_revision_missing_fields_errs() {
        let err = parse_revision("abc1234\0wip").unwrap_err();
        assert!(err.contains("unexpected"));
    }

    #[test]
    fn parse_revision_trims_trailing_newline() {
        // jj tends to append a newline after the template output.
        let rev = parse_revision("abc\0desc\0\n").unwrap();
        assert_eq!(rev.change_id, "abc");
    }

    // --- parse_status ----------------------------------------------------

    #[test]
    fn parse_status_clean() {
        let s = parse_status("The working copy has no changes.\n");
        assert!(s.clean);
        assert_eq!(s.lines.len(), 1);
    }

    #[test]
    fn parse_status_dirty() {
        let stdout = "M src/lib.rs\nA README.md\nChanges since main:\n";
        let s = parse_status(stdout);
        assert!(!s.clean);
        assert_eq!(s.lines.len(), 3);
    }

    #[test]
    fn parse_status_empty() {
        let s = parse_status("");
        // Empty stdout isn't "clean" by our heuristic (no "no changes" marker).
        assert!(!s.clean);
        assert!(s.lines.is_empty());
    }

    // --- jj_binary env override -----------------------------------------

    #[test]
    fn jj_binary_honors_env_override() {
        // Use a process-unique sentinel path so the test is independent of
        // whatever the dev machine has at the candidate locations.
        let sentinel = "/tmp/roost-fake-jj-override-only-for-test";
        // SAFETY: tests in the same crate run on separate threads by default;
        // set_var is unsafe since Rust 1.79. We accept the risk because no
        // other test reads $ROOST_JJ_PATH.
        unsafe { std::env::set_var("ROOST_JJ_PATH", sentinel) };
        let resolved = jj_binary().unwrap();
        unsafe { std::env::remove_var("ROOST_JJ_PATH") };
        assert_eq!(resolved, sentinel);
    }
}
