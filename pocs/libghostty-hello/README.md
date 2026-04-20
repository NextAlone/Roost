# M-1 / M0.0 / M0.2 POC: libghostty hello

> **Frozen.** Development continues in [`apps/Roost/`](../../apps/Roost/).
> This POC remains as a minimal reference for the terminal-engine integration
> path that validated M-1 through M0.2 (see repo-root `design.md`).

Stack validated here:

- `GhosttyKit.xcframework` (prebuilt, `manaflow-ai/ghostty` release) linked
  into a SwiftUI app with `-lc++ -framework Metal/QuartzCore/IOSurface/Carbon`.
- `ghostty_init(argc, argv)` before any other ghostty API; otherwise
  `ghostty_config_new` segfaults.
- `ghostty_surface_config_s.platform.macos.nsview = self` hands libghostty a
  native NSView; it mounts its own `CAMetalLayer` and runs the shell/PTY.
- Keyboard forwarded via `ghostty_surface_key` with `keycode = NSEvent.keyCode`,
  `unshifted_codepoint`, modifier bits, and PUA/control-char filtered `text`.
- `wait_after_command = true` + `close_surface_cb` handles graceful agent
  exit and hands UI control back to SwiftUI.

## Build

```bash
./scripts/fetch-prebuilt-xcframework.sh
./scripts/build-rust.sh
xcodegen generate
open LibghosttyHello.xcodeproj
```

See `apps/Roost/README.md` (or `design.md`) for the canonical setup.
