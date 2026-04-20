//! Persistent control connection over Unix socket.
//!
//! M7 needs server-pushed events (`session_state`, `session_exited`,
//! `session_osc`) which a per-call connect can't see. This module gives the
//! client a long-lived `Connection`:
//!
//! * one background **reader thread** (`std::thread`, not tokio — keeps the
//!   bridge staticlib lean) that parses each newline frame, demuxes
//!   responses to per-id `mpsc::Sender`s and routes notifications to an
//!   events channel.
//! * a `Mutex<UnixStream>` for the write half — multiple sync callers can
//!   issue requests concurrently without serializing through tokio.
//! * pending-request map that the reader fills in on response and the read
//!   thread drains with `Disconnected` on EOF / error.
//!
//! Reconnect logic lives in `lib.rs::Client`; this module just owns one
//! connection at a time.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

use roost_core::rpc::{Hello, HelloAck, Request, Response};
use serde::Serialize;
use serde::de::DeserializeOwned;
use serde_json::Value;

use crate::{CLIENT_VERSION, ClientError, Result};

/// One server→client notification frame. Mirrors JSON-RPC 2.0 notifications
/// (a request with no `id`).
#[derive(Debug, Clone)]
pub struct Event {
    pub method: String,
    pub params: Value,
}

type PendingMap = Arc<Mutex<HashMap<u64, std::sync::mpsc::Sender<Result<Value>>>>>;

pub struct Connection {
    write: Arc<Mutex<UnixStream>>,
    pending: PendingMap,
    next_id: AtomicU64,
    /// Events sink. `try_take_events` hands the receiver to a subscriber;
    /// only one subscriber is supported (mpsc is single-consumer).
    events_rx: Mutex<Option<std::sync::mpsc::Receiver<Event>>>,
    /// Set true by the reader on EOF / parse error. Subsequent calls fail
    /// fast with `Disconnected`.
    closed: Arc<std::sync::atomic::AtomicBool>,
    _reader: JoinHandle<()>,
}

impl Connection {
    pub fn connect(socket: &str, token: &str, hello_timeout: Duration) -> Result<Self> {
        let stream = UnixStream::connect(socket)?;
        stream.set_read_timeout(Some(hello_timeout))?;
        stream.set_write_timeout(Some(hello_timeout))?;

        // Hello on the same stream before splitting — handshake is request-
        // reply with predictable timing.
        let mut handshake = stream.try_clone()?;
        let hello = Hello {
            auth_token: token.to_string(),
            client_version: CLIENT_VERSION.to_string(),
        };
        write_frame(&mut handshake, &hello)?;
        let mut handshake_reader = BufReader::new(stream.try_clone()?);
        let ack: HelloAck = read_frame(&mut handshake_reader)?;
        if !ack.ok {
            return Err(map_hello_error(ack));
        }

        // Promote to "long calls allowed" timeouts. Reader thread doesn't
        // need a timeout — it blocks on read indefinitely until either a
        // frame arrives or the peer closes.
        stream.set_read_timeout(None)?;
        // Writers want a generous ceiling so a wedged peer doesn't block
        // forever.
        stream.set_write_timeout(Some(Duration::from_secs(30)))?;

        let read_half = BufReader::new(stream.try_clone()?);
        let write_half = Arc::new(Mutex::new(stream));
        let pending: PendingMap = Arc::new(Mutex::new(HashMap::new()));
        let closed = Arc::new(std::sync::atomic::AtomicBool::new(false));

        let (events_tx, events_rx) = std::sync::mpsc::channel::<Event>();

        let reader_handle = {
            let pending = pending.clone();
            let closed = closed.clone();
            thread::Builder::new()
                .name("roost-client-reader".into())
                .spawn(move || reader_loop(read_half, pending, events_tx, closed))
                .expect("spawn reader thread")
        };

        Ok(Self {
            write: write_half,
            pending,
            next_id: AtomicU64::new(1),
            events_rx: Mutex::new(Some(events_rx)),
            closed,
            _reader: reader_handle,
        })
    }

    pub fn is_alive(&self) -> bool {
        !self.closed.load(Ordering::SeqCst)
    }

    /// Hand out the events receiver — only callable once per connection.
    /// roost-attach uses it; the bridge doesn't subscribe to events in M7.
    pub fn take_events(&self) -> Option<std::sync::mpsc::Receiver<Event>> {
        self.events_rx.lock().ok().and_then(|mut g| g.take())
    }

    pub fn call<P: Serialize, R: DeserializeOwned>(
        &self,
        method: &str,
        params: &P,
        timeout: Duration,
    ) -> Result<R> {
        if !self.is_alive() {
            return Err(disconnected());
        }
        let id = self.next_id.fetch_add(1, Ordering::SeqCst);
        let req = Request::new(id, method, params);

        let (tx, rx) = std::sync::mpsc::channel::<Result<Value>>();
        {
            let mut g = self.pending.lock().unwrap_or_else(|p| p.into_inner());
            g.insert(id, tx);
        }

        // Write under lock so concurrent callers don't interleave bytes.
        {
            let mut w = self.write.lock().unwrap_or_else(|p| p.into_inner());
            if let Err(e) = write_frame(&mut w, &req) {
                self.pending
                    .lock()
                    .unwrap_or_else(|p| p.into_inner())
                    .remove(&id);
                return Err(e);
            }
        }

        let value = match rx.recv_timeout(timeout) {
            Ok(Ok(v)) => v,
            Ok(Err(e)) => return Err(e),
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                self.pending
                    .lock()
                    .unwrap_or_else(|p| p.into_inner())
                    .remove(&id);
                return Err(ClientError::Timeout);
            }
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                return Err(disconnected());
            }
        };
        serde_json::from_value(value).map_err(|e| ClientError::Decode(e.to_string()))
    }
}

impl Drop for Connection {
    fn drop(&mut self) {
        // Best-effort: shut down both halves so the reader thread breaks
        // out of its blocking read.
        if let Ok(w) = self.write.lock() {
            let _ = w.shutdown(std::net::Shutdown::Both);
        }
    }
}

fn reader_loop(
    mut reader: BufReader<UnixStream>,
    pending: PendingMap,
    events_tx: std::sync::mpsc::Sender<Event>,
    closed: Arc<std::sync::atomic::AtomicBool>,
) {
    let mut buf = String::new();
    loop {
        buf.clear();
        let n = match reader.read_line(&mut buf) {
            Ok(n) => n,
            Err(_) => break,
        };
        if n == 0 {
            break;
        }
        let line = buf.trim_end_matches('\n');
        let raw: Value = match serde_json::from_str(line) {
            Ok(v) => v,
            Err(_) => continue,
        };

        // Demux: id present → response; otherwise treat as notification.
        if let Some(id_value) = raw.get("id") {
            if let Some(id) = id_value.as_u64() {
                let resp: Response = match serde_json::from_value(raw) {
                    Ok(r) => r,
                    Err(_) => continue,
                };
                let mut g = pending.lock().unwrap_or_else(|p| p.into_inner());
                if let Some(tx) = g.remove(&id) {
                    let outcome = if let Some(err) = resp.error {
                        Err(ClientError::Rpc {
                            code: err.code,
                            message: err.message,
                        })
                    } else {
                        Ok(resp.result.unwrap_or(Value::Null))
                    };
                    let _ = tx.send(outcome);
                }
                continue;
            }
        }

        if let Some(method) = raw.get("method").and_then(|v| v.as_str()) {
            let event = Event {
                method: method.to_string(),
                params: raw.get("params").cloned().unwrap_or(Value::Null),
            };
            let _ = events_tx.send(event);
        }
    }

    // Connection lost — fail any pending callers.
    closed.store(true, Ordering::SeqCst);
    let mut g = pending.lock().unwrap_or_else(|p| p.into_inner());
    for (_, tx) in g.drain() {
        let _ = tx.send(Err(disconnected()));
    }
}

fn write_frame<T: Serialize>(stream: &mut UnixStream, msg: &T) -> Result<()> {
    let mut line = serde_json::to_string(msg).map_err(|e| ClientError::Decode(e.to_string()))?;
    line.push('\n');
    stream.write_all(line.as_bytes())?;
    stream.flush()?;
    Ok(())
}

fn read_frame<T: DeserializeOwned>(reader: &mut BufReader<UnixStream>) -> Result<T> {
    let mut buf = String::new();
    let n = reader.read_line(&mut buf)?;
    if n == 0 {
        return Err(ClientError::Io(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "server closed connection",
        )));
    }
    serde_json::from_str(buf.trim_end_matches('\n'))
        .map_err(|e| ClientError::Decode(e.to_string()))
}

fn disconnected() -> ClientError {
    ClientError::Io(std::io::Error::new(
        std::io::ErrorKind::BrokenPipe,
        "hostd connection closed",
    ))
}

fn map_hello_error(ack: HelloAck) -> ClientError {
    let msg = ack.error.unwrap_or_else(|| "(no message)".into());
    if msg.contains("auth_token") {
        ClientError::Auth(msg)
    } else if msg.contains("version") {
        ClientError::VersionMismatch {
            server: ack.server_version,
        }
    } else {
        ClientError::Manifest(msg)
    }
}

