//! Process-wide event bus for server→client notifications.
//!
//! Single broadcast channel; every alive control connection holds a
//! `Receiver`. Events are pre-serialized as a `(method, params)` pair and
//! the per-conn write task turns them into JSON-RPC notification frames.

use roost_core::rpc::{
    SessionExitedEvent, SessionOscEvent, SessionStateEvent, events as event_methods,
};
use serde_json::Value;
use tokio::sync::broadcast;

/// Capacity is generous: a busy session can fire OSCs at every prompt.
/// Subscribers that lag past this just lose old events (broadcast policy).
const CAPACITY: usize = 1024;

#[derive(Debug, Clone)]
pub struct EventEnvelope {
    pub method: &'static str,
    pub params: Value,
}

#[derive(Clone)]
pub struct EventBus {
    tx: broadcast::Sender<EventEnvelope>,
}

impl EventBus {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(CAPACITY);
        Self { tx }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<EventEnvelope> {
        self.tx.subscribe()
    }

    pub fn emit_session_state(&self, evt: SessionStateEvent) {
        let _ = self.tx.send(EventEnvelope {
            method: event_methods::SESSION_STATE,
            params: serde_json::to_value(evt).unwrap_or(Value::Null),
        });
    }

    pub fn emit_session_exited(&self, evt: SessionExitedEvent) {
        let _ = self.tx.send(EventEnvelope {
            method: event_methods::SESSION_EXITED,
            params: serde_json::to_value(evt).unwrap_or(Value::Null),
        });
    }

    pub fn emit_session_osc(&self, evt: SessionOscEvent) {
        let _ = self.tx.send(EventEnvelope {
            method: event_methods::SESSION_OSC,
            params: serde_json::to_value(evt).unwrap_or(Value::Null),
        });
    }
}

impl Default for EventBus {
    fn default() -> Self {
        Self::new()
    }
}
