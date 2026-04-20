//! `.roost/config.json` setup / teardown hook runner (M5).
//!
//! Config shape:
//!
//! ```json
//! { "setup":    ["npm install", "echo ready"],
//!   "teardown": ["rm -rf node_modules"] }
//! ```
//!
//! Both fields optional; missing file => no-op. Commands run sequentially
//! under `$SHELL -lc <cmd>` so they inherit the user's login PATH (same
//! reason as `roost_prepare_session`: GUI apps get launchd's thin PATH).
//! `cwd` is the caller-supplied workspace dir. A failing step does not
//! abort the remaining steps — we record every outcome and let the caller
//! warn in UI while the workspace operation proceeds.

use std::path::{Path, PathBuf};
use std::process::Command;

use serde::Deserialize;

#[derive(Debug, Default, Deserialize)]
pub struct HookConfig {
    #[serde(default)]
    pub setup: Vec<String>,
    #[serde(default)]
    pub teardown: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    Setup,
    Teardown,
}

impl Phase {
    fn as_str(self) -> &'static str {
        match self {
            Phase::Setup => "setup",
            Phase::Teardown => "teardown",
        }
    }
}

#[derive(Debug, Clone)]
pub struct HookStepResult {
    pub phase: Phase,
    pub index: usize,    // 1-based
    pub total: usize,
    pub command: String,
    pub exit_code: i32, // -1 = failed to spawn
    pub stderr_tail: String,
}

/// Resolve `<project_root>/.roost/config.json`. Missing file => empty
/// config; malformed JSON => `Err` so the caller can surface it. IO errors
/// other than NotFound also propagate.
pub fn load_config(project_root: &Path) -> Result<HookConfig, String> {
    let path: PathBuf = project_root.join(".roost").join("config.json");
    let bytes = match std::fs::read(&path) {
        Ok(b) => b,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            return Ok(HookConfig::default());
        }
        Err(e) => return Err(format!("read {}: {e}", path.display())),
    };
    serde_json::from_slice::<HookConfig>(&bytes)
        .map_err(|e| format!("parse {}: {e}", path.display()))
}

/// Run setup hooks. Returns one result per command attempted.
pub fn run_setup(project_root: &Path, workspace_dir: &Path) -> Result<Vec<HookStepResult>, String> {
    let cfg = load_config(project_root)?;
    Ok(run_phase(Phase::Setup, &cfg.setup, workspace_dir, &resolve_shell()))
}

pub fn run_teardown(
    project_root: &Path,
    workspace_dir: &Path,
) -> Result<Vec<HookStepResult>, String> {
    let cfg = load_config(project_root)?;
    Ok(run_phase(Phase::Teardown, &cfg.teardown, workspace_dir, &resolve_shell()))
}

fn resolve_shell() -> String {
    std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".to_string())
}

fn run_phase(phase: Phase, cmds: &[String], cwd: &Path, shell: &str) -> Vec<HookStepResult> {
    let total = cmds.len();
    cmds.iter()
        .enumerate()
        .map(|(i, cmd)| run_one(phase, i + 1, total, cmd, shell, cwd))
        .collect()
}

fn run_one(
    phase: Phase,
    index: usize,
    total: usize,
    cmd: &str,
    shell: &str,
    cwd: &Path,
) -> HookStepResult {
    let mut command = Command::new(shell);
    command.arg("-lc").arg(cmd).current_dir(cwd);
    match command.output() {
        Ok(out) => {
            let code = out.status.code().unwrap_or(-1);
            let stderr = String::from_utf8_lossy(&out.stderr);
            HookStepResult {
                phase,
                index,
                total,
                command: cmd.to_string(),
                exit_code: code,
                stderr_tail: tail(&stderr, 8 * 1024),
            }
        }
        Err(e) => HookStepResult {
            phase,
            index,
            total,
            command: cmd.to_string(),
            exit_code: -1,
            stderr_tail: format!("spawn {shell}: {e}"),
        },
    }
}

fn tail(s: &str, max_bytes: usize) -> String {
    if s.len() <= max_bytes {
        return s.to_string();
    }
    let start = s.len() - max_bytes;
    let boundary = s
        .char_indices()
        .find(|(i, _)| *i >= start)
        .map(|(i, _)| i)
        .unwrap_or(start);
    s[boundary..].to_string()
}

/// Serialize one result as a single line for swift-bridge transport.
/// Fields are `\u{1f}`-separated; rows are `\n`-separated.
/// phase␟index␟total␟exit_code␟command␟stderr_tail
pub fn serialize(results: &[HookStepResult]) -> String {
    let mut out = String::new();
    for r in results {
        out.push_str(r.phase.as_str());
        out.push('\u{1f}');
        out.push_str(&r.index.to_string());
        out.push('\u{1f}');
        out.push_str(&r.total.to_string());
        out.push('\u{1f}');
        out.push_str(&r.exit_code.to_string());
        out.push('\u{1f}');
        out.push_str(&escape(&r.command));
        out.push('\u{1f}');
        out.push_str(&escape(&r.stderr_tail));
        out.push('\n');
    }
    out
}

/// Replace any `\n` / `\u{1f}` in fields so Swift can split unambiguously.
/// We keep bytes printable-ish; callers that need the raw text can drop
/// this if they switch to JSON later.
fn escape(s: &str) -> String {
    s.replace('\u{1f}', " ").replace('\n', " ")
}

// MARK: - tests

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn tmpdir(label: &str) -> PathBuf {
        let mut p = std::env::temp_dir();
        p.push(format!(
            "roost-hooks-{}-{}-{}",
            label,
            std::process::id(),
            rand_suffix()
        ));
        fs::create_dir_all(&p).unwrap();
        p
    }

    // Avoid pulling `rand`; good-enough uniqueness via nanos.
    fn rand_suffix() -> String {
        use std::time::{SystemTime, UNIX_EPOCH};
        let n = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        format!("{n:x}")
    }

    fn write_config(root: &Path, body: &str) {
        let dir = root.join(".roost");
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("config.json"), body).unwrap();
    }

    #[test]
    fn missing_config_is_empty() {
        let root = tmpdir("missing");
        let cfg = load_config(&root).unwrap();
        assert!(cfg.setup.is_empty() && cfg.teardown.is_empty());
    }

    #[test]
    fn empty_object_is_empty() {
        let root = tmpdir("empty");
        write_config(&root, "{}");
        let cfg = load_config(&root).unwrap();
        assert!(cfg.setup.is_empty() && cfg.teardown.is_empty());
    }

    #[test]
    fn malformed_json_errs() {
        let root = tmpdir("malformed");
        write_config(&root, "{not json");
        let err = load_config(&root).unwrap_err();
        assert!(err.contains("parse"), "got {err}");
    }

    // Use /bin/sh directly in tests so we don't depend on the test host's
    // login shell (fish, zsh, etc.) where `>&2` redirect syntax differs.
    const TEST_SH: &str = "/bin/sh";

    #[test]
    fn setup_runs_and_reports_exit_codes() {
        let cmds = vec![
            "true".to_string(),
            "false".to_string(),
            "echo hi >&2".to_string(),
        ];
        let cwd = tmpdir("cwd-setup");
        let results = run_phase(Phase::Setup, &cmds, &cwd, TEST_SH);
        assert_eq!(results.len(), 3);
        assert_eq!(results[0].exit_code, 0);
        assert_eq!(results[1].exit_code, 1);
        assert_eq!(results[2].exit_code, 0);
        assert!(results[2].stderr_tail.contains("hi"));
        assert!(results.iter().all(|r| r.phase == Phase::Setup));
        assert_eq!(results[0].total, 3);
        assert_eq!(results[1].index, 2);
    }

    #[test]
    fn teardown_honors_cwd() {
        let cmds = vec!["pwd > pwd.txt".to_string()];
        let cwd = tmpdir("cwd-teardown");
        let results = run_phase(Phase::Teardown, &cmds, &cwd, TEST_SH);
        assert_eq!(results.len(), 1);
        assert_eq!(results[0].exit_code, 0);
        let got = fs::read_to_string(cwd.join("pwd.txt")).unwrap();
        let got_trim = got.trim();
        let want = cwd.to_string_lossy();
        // macOS tempdir under /var often resolves to /private/var; accept both.
        assert!(
            got_trim.ends_with(want.as_ref())
                || got_trim.ends_with(&format!("/private{want}")),
            "pwd {got_trim:?} did not match cwd {want:?}",
        );
    }

    #[test]
    fn config_drives_phase_selection() {
        // End-to-end: writing config, load_config picks up both arrays.
        let root = tmpdir("both");
        write_config(
            &root,
            r#"{ "setup": ["true"], "teardown": ["true", "true"] }"#,
        );
        let cfg = load_config(&root).unwrap();
        assert_eq!(cfg.setup.len(), 1);
        assert_eq!(cfg.teardown.len(), 2);
    }

    #[test]
    fn serialize_round_trip_fields() {
        let results = vec![HookStepResult {
            phase: Phase::Setup,
            index: 1,
            total: 2,
            command: "echo a\nb".into(),
            exit_code: 42,
            stderr_tail: "boom\n".into(),
        }];
        let ser = serialize(&results);
        // Fields sane, newlines in payload escaped to spaces.
        let line = ser.lines().next().unwrap();
        let fields: Vec<&str> = line.split('\u{1f}').collect();
        assert_eq!(fields.len(), 6);
        assert_eq!(fields[0], "setup");
        assert_eq!(fields[1], "1");
        assert_eq!(fields[2], "2");
        assert_eq!(fields[3], "42");
        assert_eq!(fields[4], "echo a b");
        assert_eq!(fields[5], "boom ");
    }
}
