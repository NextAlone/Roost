//! SQLite skeleton. Tracks only schema version today; concrete tables follow
//! when the bridge starts persisting projects (M8). Goal here is to exercise
//! the path / perms / pool wiring on first boot so production failures don't
//! all surface in one shot later.

use anyhow::{Context, Result};
use roost_core::dto::{AgentSpec, SessionId, SessionInfo, SessionState};
use roost_core::paths;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::{ConnectOptions, Row, SqlitePool};
use std::str::FromStr;
use std::time::SystemTime;
use tokio::fs;
use tracing::{info, warn};

const SCHEMA_VERSION: i64 = 2;

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

    // Read the highest recorded version. None = brand new db; less than
    // SCHEMA_VERSION = old client wrote a lower number, we silently bump
    // (additive migrations only); greater = future client wrote ahead of
    // us, refuse so we don't quietly downgrade their data.
    let actual: Option<i64> =
        sqlx::query_scalar("SELECT MAX(v) FROM schema_version")
            .fetch_one(&pool)
            .await?;
    if let Some(v) = actual {
        if v > SCHEMA_VERSION {
            anyhow::bail!(
                "sqlite schema v{} is newer than this hostd's v{}; refusing to open",
                v,
                SCHEMA_VERSION
            );
        }
    }
    if actual != Some(SCHEMA_VERSION) {
        sqlx::query("DELETE FROM schema_version").execute(&pool).await?;
        sqlx::query("INSERT INTO schema_version (v) VALUES (?)")
            .bind(SCHEMA_VERSION)
            .execute(&pool)
            .await?;
    }

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS sessions (\
            id TEXT PRIMARY KEY,\
            agent_kind TEXT NOT NULL,\
            working_directory TEXT NOT NULL,\
            agent_spec_json TEXT NOT NULL,\
            state TEXT NOT NULL,\
            pid INTEGER,\
            exit_code INTEGER,\
            created_at_epoch_ms INTEGER NOT NULL,\
            exited_at_epoch_ms INTEGER\
        )",
    )
    .execute(&pool)
    .await?;

    let reconciled = reconcile_orphans(&pool).await?;
    if reconciled > 0 {
        info!("reconciled {} orphan running sessions → exited_lost", reconciled);
    }

    info!("sqlite ready at {}", db_path.display());
    Ok(pool)
}

/// Mark every `running` session as `exited_lost` — they belong to a hostd
/// instance that's gone (we just started; no in-memory registry has them).
async fn reconcile_orphans(pool: &SqlitePool) -> Result<u64> {
    let now = now_ms() as i64;
    let res = sqlx::query(
        "UPDATE sessions \
            SET state = 'exited_lost', exited_at_epoch_ms = ? \
            WHERE state = 'running' OR state = 'starting' OR state = 'detached'",
    )
    .bind(now)
    .execute(pool)
    .await?;
    Ok(res.rows_affected())
}

pub async fn insert_session(pool: &SqlitePool, info: &SessionInfo, spec: &AgentSpec) {
    let json = match serde_json::to_string(spec) {
        Ok(s) => s,
        Err(e) => {
            warn!("session spec serialize failed: {e}");
            "{}".to_string()
        }
    };
    let r = sqlx::query(
        "INSERT INTO sessions \
            (id, agent_kind, working_directory, agent_spec_json, state, pid, exit_code, created_at_epoch_ms, exited_at_epoch_ms) \
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(info.id.to_string())
    .bind(&info.agent_kind)
    .bind(&info.working_directory)
    .bind(json)
    .bind(info.state.as_str())
    .bind(info.pid.map(|p| p as i64))
    .bind(info.exit_code.map(|c| c as i64))
    .bind(info.created_at_epoch_ms as i64)
    .bind::<Option<i64>>(None)
    .execute(pool)
    .await;
    if let Err(e) = r {
        warn!("insert_session failed: {e}");
    }
}

/// Currently unused — only `update_session_exit` is plumbed through. Kept
/// for future M8 P4 attach-state transitions (e.g. detach-event persisted
/// so adopt sees the right tab status).
#[allow(dead_code)]
pub async fn update_session_state(pool: &SqlitePool, id: SessionId, state: SessionState) {
    let r = sqlx::query("UPDATE sessions SET state = ? WHERE id = ?")
        .bind(state.as_str())
        .bind(id.to_string())
        .execute(pool)
        .await;
    if let Err(e) = r {
        warn!("update_session_state({id}) failed: {e}");
    }
}

pub async fn update_session_exit(
    pool: &SqlitePool,
    id: SessionId,
    code: Option<i32>,
) {
    let r = sqlx::query(
        "UPDATE sessions \
            SET state = 'exited', exit_code = ?, exited_at_epoch_ms = ? \
            WHERE id = ?",
    )
    .bind(code.map(|c| c as i64))
    .bind(now_ms() as i64)
    .bind(id.to_string())
    .execute(pool)
    .await;
    if let Err(e) = r {
        warn!("update_session_exit({id}) failed: {e}");
    }
}

/// Most-recent first. Includes both live (Running/Detached) and historical
/// (Exited/ExitedLost) rows so callers can render a unified timeline.
pub async fn list_session_history(pool: &SqlitePool) -> Result<Vec<SessionInfo>> {
    let rows = sqlx::query(
        "SELECT id, agent_kind, working_directory, agent_spec_json, state, pid, exit_code, \
                created_at_epoch_ms \
            FROM sessions ORDER BY created_at_epoch_ms DESC",
    )
    .fetch_all(pool)
    .await?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        let id_str: String = row.try_get("id")?;
        let state_str: String = row.try_get("state")?;
        let agent_kind: String = row.try_get("agent_kind")?;
        let working_directory: String = row.try_get("working_directory")?;
        let agent_spec_json: String = row.try_get("agent_spec_json")?;
        let pid: Option<i64> = row.try_get("pid")?;
        let exit_code: Option<i64> = row.try_get("exit_code")?;
        let created: i64 = row.try_get("created_at_epoch_ms")?;

        let Ok(id) = id_str.parse::<SessionId>() else {
            warn!("skipping unparseable session id {id_str:?}");
            continue;
        };
        let Ok(state) = state_str.parse::<SessionState>() else {
            warn!("skipping unparseable session state {state_str:?}");
            continue;
        };
        out.push(SessionInfo {
            id,
            agent_kind,
            working_directory,
            state,
            pid: pid.map(|p| p as u32),
            exit_code: exit_code.map(|c| c as i32),
            created_at_epoch_ms: created as u64,
            agent_spec_json: if agent_spec_json.is_empty() {
                None
            } else {
                Some(agent_spec_json)
            },
        });
    }
    Ok(out)
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}
