//! Swift-facing bridge for Roost's Rust core.
//!
//! M0.1 surface: `roost_greet` / `roost_bridge_version` smoke tests.
//! M0.2 surface: `roost_prepare_session(agent)` — returns the exec spec a
//! libghostty surface needs to spawn an agent CLI. Still no persistence; real
//! `RoostCore` state lives in §4 of design.md and arrives later.

use std::path::{Path, PathBuf};

#[swift_bridge::bridge]
mod ffi {
    #[swift_bridge(swift_repr = "struct")]
    struct SessionSpec {
        /// Shell-style command string (ghostty parses this itself).
        /// Empty => let ghostty start the user's login shell.
        command: String,
        working_directory: String,
        agent_kind: String,
    }

    extern "Rust" {
        fn roost_greet(name: &str) -> String;
        fn roost_bridge_version() -> String;
        fn roost_prepare_session(agent: &str) -> SessionSpec;
    }
}

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

fn roost_prepare_session(agent: &str) -> ffi::SessionSpec {
    let agent_norm = agent.trim().to_lowercase();
    let home = std::env::var("HOME").unwrap_or_else(|_| "/".to_string());

    let command = match agent_norm.as_str() {
        "" | "shell" | "bash" | "zsh" => String::new(),
        name => resolve_command_for(name).unwrap_or_else(|| {
            // Fallback: load user's login shell env, then exec the agent by
            // name. Works even if the binary is on a PATH the GUI launchd
            // didn't inherit.
            format!("/bin/zsh -il -c {name}")
        }),
    };

    ffi::SessionSpec {
        command,
        working_directory: home,
        agent_kind: agent_norm,
    }
}

/// Walk the usual binary install locations on macOS for a given agent name.
fn resolve_command_for(agent: &str) -> Option<String> {
    let home = std::env::var("HOME").ok()?;
    let candidates = [
        PathBuf::from(format!("{home}/.local/bin/{agent}")),
        PathBuf::from(format!("/opt/homebrew/bin/{agent}")),
        PathBuf::from(format!("/usr/local/bin/{agent}")),
    ];
    candidates
        .into_iter()
        .find(|p| is_executable(p))
        .map(|p| p.to_string_lossy().into_owned())
}

fn is_executable(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    p.metadata()
        .ok()
        .filter(|m| m.is_file())
        .map(|m| m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}
