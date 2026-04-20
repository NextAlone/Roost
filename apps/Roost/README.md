# Roost (app)

macOS SwiftUI app that orchestrates CLI coding agents in a libghostty-rendered
terminal. Rust backend in [`crates/roost-bridge`](../../crates/roost-bridge)
exposes the session plumbing via [swift-bridge](https://github.com/chinedufn/swift-bridge).

Status: **M0 walking skeleton.** One agent, one surface, launcher screen.
Multi-session / sidebar / jj workspace / CLI come with M1+ (see repo-root
[`design.md`](../../design.md)).

## Prerequisites

- macOS ≥ 13, Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Rust toolchain (`cargo --version` ≥ 1.85)

## One-time

`GhosttyKit.xcframework` is not vendored. Fetch it once:

```bash
# from the repo root
./pocs/libghostty-hello/scripts/fetch-prebuilt-xcframework.sh
```

This drops `vendor/GhosttyKit.xcframework/` (pinned SHA; see that script to
bump). `apps/Roost/project.yml` links from `../../vendor/`.

## Build + run

```bash
cd apps/Roost
./scripts/build-rust.sh          # first cargo build + stage Generated/
xcodegen generate
open Roost.xcodeproj
# ⌘R
```

Subsequent builds run `build-rust.sh` automatically as an Xcode pre-build phase.

## Layout

```
apps/Roost/
├── project.yml                      # XcodeGen config (target + link line)
├── scripts/build-rust.sh            # cargo build roost-bridge + stage Generated/
├── Generated/                       # gitignored; swift-bridge output + static lib
└── Sources/
    ├── App/       RoostApp, RootView, HeaderBar      # top-level shell
    ├── Launcher/  LauncherView                       # agent picker screen
    ├── Terminal/  GhosttyRuntime, TerminalNSView,    # libghostty integration
    │              TerminalView (NSViewRepresentable)
    └── Bridge/    RoostBridge (FFI facade),          # swift-bridge facade
                   GhosttyInfo
```
