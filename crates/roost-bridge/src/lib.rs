//! Swift-facing bridge for Roost's Rust core.
//!
//! Current surface is a single `greet(name)` smoke test used by the M0.1
//! walking-skeleton POC. Real `RoostCore` methods (§4 of design.md) land in
//! M0.2 and later.

#[swift_bridge::bridge]
mod ffi {
    extern "Rust" {
        fn roost_greet(name: &str) -> String;
        fn roost_bridge_version() -> String;
    }
}

fn roost_greet(name: &str) -> String {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        "Hello from Rust 👋".to_string()
    } else {
        format!("Hello, {trimmed}, from Rust 👋")
    }
}

fn roost_bridge_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}
