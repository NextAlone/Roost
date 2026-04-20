//! Well-known filesystem locations for Roost's daemon state.
//!
//! macOS-only for MVP; uses `~/Library/Application Support/roost/`.

use std::path::PathBuf;

const APP_DIR: &str = "roost";
const HOSTD_SUBDIR: &str = "hostd";
const SOCKET_NAME: &str = "hostd.sock";
const MANIFEST_NAME: &str = "manifest.json";
const DB_NAME: &str = "roost.db";

/// `~/Library/Application Support/roost/`. Falls back to `~/.roost/` if Library
/// can't be resolved (CI / sandboxed contexts).
pub fn app_support_dir() -> PathBuf {
    if let Some(base) = dirs::data_dir() {
        return base.join(APP_DIR);
    }
    if let Some(home) = dirs::home_dir() {
        return home.join(format!(".{APP_DIR}"));
    }
    PathBuf::from(format!("./.{APP_DIR}"))
}

/// `~/Library/Application Support/roost/hostd/`. Should be 0700.
pub fn hostd_dir() -> PathBuf {
    app_support_dir().join(HOSTD_SUBDIR)
}

pub fn socket_path() -> PathBuf {
    hostd_dir().join(SOCKET_NAME)
}

pub fn manifest_path() -> PathBuf {
    hostd_dir().join(MANIFEST_NAME)
}

pub fn db_path() -> PathBuf {
    app_support_dir().join(DB_NAME)
}
