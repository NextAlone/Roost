//! In-memory session table. The owner is `HostState`; consumers borrow via
//! `Arc<Registry>` and lock per call.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use bytes::Bytes;
use roost_core::dto::{SessionId, SessionInfo, SessionState};
use tokio::sync::{broadcast, mpsc};

use super::RingBuffer;

/// Live state for one PTY-backed agent. Cloned cheaply (mostly Arcs).
///
/// `stdin_tx` / `resize_tx` are `Option` so that on exit we can `take()`
/// them to drop the channels and let the spawn module's writer / resize
/// blocking tasks exit (and release the PTY master). Keep the entry in the
/// registry afterwards so `list_sessions` still surfaces the Exited row +
/// final scrollback for the UI.
pub struct SessionEntry {
    pub info: SessionInfo,
    pub stdin_tx: Option<mpsc::Sender<Bytes>>,
    /// Live PTY output, fanned out to all currently-attached subscribers.
    /// Late attachers replay `ring` first, then subscribe.
    pub broadcast_tx: broadcast::Sender<Bytes>,
    pub ring: Arc<Mutex<RingBuffer>>,
    pub resize_tx: Option<mpsc::UnboundedSender<(u16, u16)>>,
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
            // Drop senders so writer + resize spawn_blocking tasks see
            // their channels close and exit. PTY master is released as a
            // side-effect — see spawn::spawn_resize_task.
            entry.stdin_tx = None;
            entry.resize_tx = None;
        }
    }

    pub fn count(&self) -> usize {
        self.inner
            .lock()
            .unwrap_or_else(|p| p.into_inner())
            .len()
    }

    /// Hard-remove an entry. Today only used by future M8 cleanup paths;
    /// `set_exit` already drops the live channels so this is solely for
    /// reclaiming the SessionInfo row.
    #[allow(dead_code)]
    pub fn remove(&self, id: SessionId) -> Option<SessionEntry> {
        let mut g = self.inner.lock().unwrap_or_else(|p| p.into_inner());
        g.remove(&id)
    }
}
