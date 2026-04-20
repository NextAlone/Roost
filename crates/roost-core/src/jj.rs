//! Thin wrapper around the `jj` CLI (>= 0.20).
//!
//! Synchronous `std::process::Command`; calls measured in tens of ms each.
//! Async runtime is owned by the daemon, not by this module.

use std::path::Path;
use std::process::{Command, Stdio};

use crate::dto::{RevisionEntry, StatusEntry, WorkspaceEntry};

/// True if the given path (or an ancestor) is a jj repo.
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

pub fn version() -> Result<String, String> {
    let out = run(&["--version"], None)?;
    Ok(out.stdout.lines().next().unwrap_or("").trim().to_string())
}

pub fn list_workspaces(repo_dir: &str) -> Result<Vec<WorkspaceEntry>, String> {
    // Template fields NUL-separated; jj only recognizes \n \t \r \\ \" \0 escapes.
    // `WorkspaceRef` lacks `.path()`; derive from `<repo>/.worktrees/<name>`.
    let tmpl = concat!(
        r#"name ++ "\0" ++ "#,
        r#"target.change_id().short() ++ "\0" ++ "#,
        r#"target.description().first_line() ++ "\n""#,
    );

    let out = run(&["workspace", "list", "-T", tmpl], Some(repo_dir))?;
    Ok(parse_workspace_lines(&out.stdout, repo_dir))
}

/// Parse the NUL-separated template output of `jj workspace list`.
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
        &["workspace", "add", "--name", name, workspace_path],
        Some(repo_dir),
    )?;

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
    // Renames the CURRENT workspace, so cwd matters.
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
    let clean = stdout.contains("no changes");
    StatusEntry { clean, lines }
}

pub fn bookmark_create(workspace_dir: &str, name: &str) -> Result<(), String> {
    run(&["bookmark", "create", "-r", "@", name], Some(workspace_dir))?;
    Ok(())
}

pub fn bookmark_forget(workspace_dir: &str, name: &str) -> Result<(), String> {
    run(&["bookmark", "forget", name], Some(workspace_dir))?;
    Ok(())
}

struct JjOutput {
    stdout: String,
    #[allow(dead_code)]
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
        let code = output
            .status
            .code()
            .map(|c| c.to_string())
            .unwrap_or_else(|| "signal".into());
        return Err(format!(
            "jj {args:?} exited {code}\nstdout: {stdout}\nstderr: {stderr}"
        ));
    }
    Ok(JjOutput { stdout, stderr })
}

/// Resolve `jj` absolute path. GUI-launched processes inherit launchd's thin
/// PATH; walk common install locations explicitly with `ROOST_JJ_PATH` override.
pub fn jj_binary() -> Result<String, String> {
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

    Ok("jj".to_string())
}

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
        assert_eq!(derive_workspace_path(repo.to_str().unwrap(), "foo"), "");
    }

    #[test]
    fn derive_does_not_treat_file_as_dir() {
        let repo = tempdir("derive-file");
        let fake = repo.join(".worktrees").join("bar");
        fs::create_dir_all(fake.parent().unwrap()).unwrap();
        fs::write(&fake, "").unwrap();
        assert_eq!(derive_workspace_path(repo.to_str().unwrap(), "bar"), "");
    }

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
        assert_eq!(entries[1].path, "");
    }

    #[test]
    fn parse_workspace_lines_skips_malformed() {
        let stdout = "good\0id\0desc\njust-a-name\n\0\0\n";
        let entries = parse_workspace_lines(stdout, "/repo");
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].name, "good");
        assert_eq!(entries[1].name, "");
    }

    #[test]
    fn parse_workspace_lines_empty_input() {
        assert!(parse_workspace_lines("", "/repo").is_empty());
        assert!(parse_workspace_lines("\n\n", "/repo").is_empty());
    }

    #[test]
    fn parse_workspace_lines_extra_fields_are_ignored() {
        let stdout = "default\0abc\0desc\0extra\0stuff\n";
        let entries = parse_workspace_lines(stdout, "/repo");
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].change_id, "abc");
        assert_eq!(entries[0].description, "desc");
    }

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
        let rev = parse_revision("abc\0desc\0\n").unwrap();
        assert_eq!(rev.change_id, "abc");
    }

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
        assert!(!s.clean);
        assert!(s.lines.is_empty());
    }

    #[test]
    fn jj_binary_honors_env_override() {
        let sentinel = "/tmp/roost-fake-jj-override-only-for-test";
        // SAFETY: tests run on separate threads by default; no other test
        // reads $ROOST_JJ_PATH in this crate.
        unsafe { std::env::set_var("ROOST_JJ_PATH", sentinel) };
        let resolved = jj_binary().unwrap();
        unsafe { std::env::remove_var("ROOST_JJ_PATH") };
        assert_eq!(resolved, sentinel);
    }
}
