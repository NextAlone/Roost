# M0.1 POC: swift-bridge hello

> **Frozen.** Development continues in [`apps/Roost/`](../../apps/Roost/).
> This POC stays as a minimal reference for the Rust ↔ Swift FFI path.

Validates that a SwiftUI app can call into `crates/roost-bridge` through
[`swift-bridge`](https://github.com/chinedufn/swift-bridge). Zero libghostty in
this POC — just the FFI path.

## Prerequisites

- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Rust toolchain (`cargo --version` ≥ 1.85)

## Build steps

```bash
# from this directory
./scripts/build-rust.sh          # cargo build roost-bridge + stage Generated/
xcodegen generate                 # emits SwiftBridgeHello.xcodeproj
open SwiftBridgeHello.xcodeproj
# ⌘R
```

The Xcode project's pre-build script re-runs `build-rust.sh`, so after the
initial manual run you can iterate by just hitting ⌘R.

Expected: a window with a name field and "Greet" button. Clicking calls Rust
`roost_greet()` which returns a formatted string; the footer also shows
`roost_bridge_version()` read via Rust.

## Layout

| Path | Contents |
|---|---|
| `../../crates/roost-bridge/` | Rust crate (staticlib) with `#[swift_bridge::bridge]` module |
| `Generated/` (gitignored) | swift-bridge generated `RoostBridge.swift` + `SwiftBridgeCore.swift` + C headers + `libroost_bridge.a` |
| `Sources/` | Minimal SwiftUI app |
| `scripts/build-rust.sh` | Cargo build → stage into `Generated/` |

## What this validates

- [ ] `cargo build` succeeds under `.cargo/config.toml` linker override.
- [ ] swift-bridge `#[swift_bridge::bridge]` generates usable Swift + C.
- [ ] Xcode links `libroost_bridge.a` and the bridging header resolves.
- [ ] SwiftUI → `roost_greet("Roost")` → visible Rust-returned string.

Gaps (tackled in M0.2, not here):
- Async / `Result` passing over FFI.
- Tokio runtime inside `RoostCore` (not yet instantiated).
- SQLite / real workspace model.
