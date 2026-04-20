//! `roost-hostd`: long-running daemon owning the JSON-RPC listener, jj wrapper,
//! and SQLite. PTY ownership lands in M7 — for M6 the daemon is purely a
//! command-and-control plane behind the existing app behavior.

use anyhow::{Context, Result};
use std::sync::Arc;
use tokio::runtime::Builder;
use tracing::info;

mod manifest;
mod rpc_server;
mod state;
mod store;

fn main() -> Result<()> {
    init_tracing();

    // §4a: tokio multi-thread runtime, worker_threads=2.
    let runtime = Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .context("build tokio runtime")?;

    runtime.block_on(async_main())
}

fn init_tracing() {
    use tracing_subscriber::EnvFilter;
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_env("ROOST_HOSTD_LOG").unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .with_target(false)
        .try_init();
}

async fn async_main() -> Result<()> {
    info!("roost-hostd starting (version={})", roost_core::HOSTD_VERSION);

    // 1. Reconcile any stale on-disk state from a previous crash.
    manifest::reconcile_stale().await?;

    // 2. Open SQLite (skeleton; real schema lands when DTOs need persistence).
    let db = store::open().await?;

    // 3. Build shared state, generate auth token.
    let state = Arc::new(state::HostState::new(db));

    // 4. Bind UDS, write manifest, install signal handlers, accept loop.
    rpc_server::run(state).await
}
