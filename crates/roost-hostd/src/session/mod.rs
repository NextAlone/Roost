// P1 establishes plumbing; P3 wires it to RPC. Public functions exist but
// have no caller yet — silence the warnings until P3 lands.
#![allow(dead_code)]

//! Session lifecycle: one agent process + one PTY master, owned here for the
//! lifetime of `roost-hostd`. M7 P1 stands up the in-memory plumbing and
//! background I/O tasks; the RPC surface that lets clients create/kill
//! sessions lands in M7 P3.

pub mod registry;
pub mod ring;
pub mod spawn;

pub use registry::Registry;
#[allow(unused_imports)]
pub use registry::SessionEntry;
pub use ring::RingBuffer;
#[allow(unused_imports)]
pub use spawn::{SpawnError, spawn_session};
