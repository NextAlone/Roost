//! Roost core: domain model, jj CLI wrapper, well-known paths, RPC wire types.
//!
//! Linked into both `roost-hostd` (server) and `roost-client` (Rust SDK), so
//! it must stay free of tokio / sqlx / FFI deps. Pure data + sync helpers.

pub mod dto;
pub mod jj;
pub mod paths;
pub mod rpc;
pub mod session;

pub const HOSTD_VERSION: &str = env!("CARGO_PKG_VERSION");
