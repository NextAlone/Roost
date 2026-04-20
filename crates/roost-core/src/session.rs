//! Agent session preparation. Stays out of the daemon hop until M7 — bridge
//! calls this directly so the M6 PTY path is unchanged.

use crate::dto::SessionSpec;

pub fn prepare(agent: &str, working_directory: &str) -> SessionSpec {
    let agent_norm = agent.trim().to_lowercase();

    // Always wrap through the user's login shell so the agent inherits PATH /
    // rc exports (jj, node, etc.). GUI-launched apps only get launchd's thin
    // PATH; a direct exec leaves agents unable to find their siblings.
    //
    // `$SHELL` is typically populated by launchd from the user record; fall
    // back to /bin/zsh (macOS default). `-l -c` is universal across bash, zsh,
    // and fish.
    let command = match agent_norm.as_str() {
        "" | "shell" | "bash" | "zsh" | "fish" => String::new(),
        name => {
            let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".to_string());
            format!("{shell} -l -c {name}")
        }
    };

    SessionSpec {
        command,
        working_directory: working_directory.to_string(),
        agent_kind: agent_norm,
    }
}

pub fn prepare_default(agent: &str) -> SessionSpec {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/".to_string());
    prepare(agent, &home)
}
