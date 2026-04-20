# M-1 POC: libghostty hello

Goal: prove `GhosttyKit.xcframework` can be built from upstream `ghostty-org/ghostty`, imported into a SwiftUI app, and render an interactive `bash` pane.

No Rust in this POC. Pure Swift + C FFI.

## Prerequisites

- macOS ≥ 13
- Xcode 16+ (or a recent command-line Swift toolchain)
- Zig ≥ 0.15.2 (install via nix, asdf, or official tarball)
- `curl`, `tar`

## Build steps

```bash
# 1. Fetch ghostty at a pinned commit (writes to ../../vendor/ghostty)
./scripts/fetch-ghostty.sh

# 2. Build GhosttyKit.xcframework
./scripts/build-xcframework.sh
# → ../../vendor/ghostty/zig-out/GhosttyKit.xcframework

# 3. (later) Open the Xcode project and build the hello app
#    open Hello.xcodeproj
```

## What this POC validates

- `zig build -Demit-xcframework=true -Demit-macos-app=false` produces a usable `GhosttyKit.xcframework` against a specific ghostty SHA.
- A minimal SwiftUI app can link that xcframework and render a surface.
- PTY attached to `bash` is interactive (keyboard → shell, shell output → surface).

If any of the three fails, the Roost architecture changes (switch to SwiftTerm or build a custom renderer). See `design.md` §M-1 in the repo root.

## Pinning

`scripts/fetch-ghostty.sh` pins a ghostty commit via `GHOSTTY_REV`. Bump by editing that variable. Keep it tracking `ghostty-org/ghostty` `main` for now; once M-1 passes, lock to a known-good SHA.

## Status

- [ ] `fetch-ghostty.sh` pulls source
- [ ] `build-xcframework.sh` produces xcframework
- [ ] Xcode project renders empty surface
- [ ] Keyboard + PTY + bash integration works
