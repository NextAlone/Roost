//! SQLite skeleton. Tracks only schema version today; concrete tables follow
//! when the bridge starts persisting projects (M8). Goal here is to exercise
//! the path / perms / pool wiring on first boot so production failures don't
//! all surface in one shot later.

use anyhow::{Context, Result};
use roost_core::paths;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::{ConnectOptions, SqlitePool};
use std::str::FromStr;
use tokio::fs;
use tracing::info;

const SCHEMA_VERSION: i64 = 1;

pub async fn open() -> Result<SqlitePool> {
    let app = paths::app_support_dir();
    fs::create_dir_all(&app)
        .await
        .with_context(|| format!("create app dir {}", app.display()))?;

    let db_path = paths::db_path();
    let url = format!("sqlite://{}?mode=rwc", db_path.display());
    let mut opts = SqliteConnectOptions::from_str(&url)?
        .create_if_missing(true)
        .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal);
    opts = opts.disable_statement_logging();

    let pool = SqlitePoolOptions::new()
        .max_connections(4)
        .connect_with(opts)
        .await
        .with_context(|| format!("open sqlite at {}", db_path.display()))?;

    sqlx::query("CREATE TABLE IF NOT EXISTS schema_version (v INTEGER NOT NULL PRIMARY KEY)")
        .execute(&pool)
        .await?;
    sqlx::query("INSERT OR IGNORE INTO schema_version (v) VALUES (?)")
        .bind(SCHEMA_VERSION)
        .execute(&pool)
        .await?;

    info!("sqlite ready at {}", db_path.display());
    Ok(pool)
}
