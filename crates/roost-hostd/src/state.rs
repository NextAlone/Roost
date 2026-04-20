//! Shared daemon state. Kept tiny in M6 — no live sessions yet, so no
//! `HashMap<SessionId, _>`. Token generation is centralized here because the
//! RPC server, manifest writer, and (future) reauth all need it.

use std::sync::Arc;
use std::time::Instant;

use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use rand::RngCore;
use sqlx::SqlitePool;

use tokio::sync::Notify;

use crate::events::EventBus;
use crate::session::Registry;

pub struct HostState {
    pub auth_token: String,
    pub started_at: Instant,
    pub started_at_epoch_ms: u64,
    #[allow(dead_code)]
    pub db: SqlitePool,
    pub sessions: Arc<Registry>,
    pub events: EventBus,
    /// Notified once when a `shutdown(Stop)` RPC arrives or a SIGTERM/SIGINT
    /// fires; the rpc_server accept loop awaits this to break.
    pub shutdown: Arc<Notify>,
}

impl HostState {
    pub fn new(db: SqlitePool) -> Self {
        let mut bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut bytes);
        let auth_token = URL_SAFE_NO_PAD.encode(bytes);
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);

        Self {
            auth_token,
            started_at: Instant::now(),
            started_at_epoch_ms: now,
            db,
            sessions: Arc::new(Registry::new()),
            events: EventBus::new(),
            shutdown: Arc::new(Notify::new()),
        }
    }

    pub fn uptime_secs(&self) -> u64 {
        self.started_at.elapsed().as_secs()
    }
}
