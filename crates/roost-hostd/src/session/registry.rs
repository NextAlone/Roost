//! In-memory session table. The owner is `HostState`; consumers borrow via
//! `Arc<Registry>` and lock per call.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use bytes::Bytes;
use roost_core::dto::{SessionId, SessionInfo, SessionState};
use tokio::sync::{broadcast, mpsc};

use super::RingBuffer;

/// Live state for one PTY-backed agent. Cloned cheaply (mostly Arcs).
pub struct SessionEntry {
    pub info: SessionInfo,
    /// Sender into the writer task — bytes pushed here flow into the PTY
    /// master. Dropping the last sender ends the writer task and EOFs the
    /// agent's stdin (which is what we want when killing).
    pub stdin_tx: mpsc::Sender<Bytes>,
    /// Live PTY output, fanned out to all currently-attached subscribers.
    /// Late attachers replay `ring` first, then subscribe.
    pub broadcast_tx: broadcast::Sender<Bytes>,
    pub ring: Arc<Mutex<RingBuffer>>,
    /// Sender to deliver a resize request to the spawn task.
    pub resize_tx: mpsc::UnboundedSender<(u16, u16)>,
}

impl SessionEntry {
    pub fn subscribe(&self) -> (Bytes, broadcast::Receiver<Bytes>) {
        let snap = self
            .ring
            .lock()
            .map(|r| r.snapshot())
            .unwrap_or_else(|p| p.into_inner().snapshot());
        (snap, self.broadcast_tx.subscribe())
    }
}

#[derive(Default)]
pub struct Registry {
    inner: Mutex<HashMap<SessionId, SessionEntry>>,
}

impl Registry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn insert(&self, entry: SessionEntry) -> SessionId {
        let id = entry.info.id;
        let mut g = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        g.insert(id, entry);
        id
    }

    pub fn list(&self) -> Vec<SessionInfo> {
        let g = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        g.values().map(|e| e.info.clone()).collect()
    }

    pub fn get_info(&self, id: SessionId) -> Option<SessionInfo> {
        let g = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        g.get(&id).map(|e| e.info.clone())
    }

    pub fn with<F, R>(&self, id: SessionId, f: F) -> Option<R>
    where
        F: FnOnce(&SessionEntry) -> R,
    {
        let g = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        g.get(&id).map(f)
    }

    pub fn set_state(&self, id: SessionId, state: SessionState) {
        let mut g = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(entry) = g.get_mut(&id) {
            entry.info.state = state;
        }
    }

    pub fn set_exit(&self, id: SessionId, code: Option<i32>) {
        let mut g = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        if let Some(entry) = g.get_mut(&id) {
            entry.info.state = SessionState::Exited;
            entry.info.exit_code = code;
        }
    }

    pub fn count(&self) -> usize {
        self.inner
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .len()
    }
}
