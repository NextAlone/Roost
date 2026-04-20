# M-1 POC: libghostty hello

Goal: prove `GhosttyKit.xcframework` can be imported into a SwiftUI app, that
`import GhosttyKit` resolves, and that libghostty symbols (starting with
`ghostty_info()`) link and run. Then grow the same project into an interactive
`bash` surface.

No Rust in this POC. Pure Swift + C FFI.

## Prerequisites

- macOS ≥ 13
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (e.g. `brew install xcodegen`
  or `nix shell nixpkgs#xcodegen`)

The zig toolchain is only required if you want to build the xcframework
yourself via `scripts/build-xcframework.sh`. The default path uses a prebuilt.

## Build steps

### Stage 1 — fetch the xcframework

```bash
./scripts/fetch-prebuilt-xcframework.sh
# → ../../vendor/GhosttyKit.xcframework
```

The script downloads a pinned `GhosttyKit.xcframework.tar.gz` from the
`manaflow-ai/ghostty` fork releases (upstream `ghostty-org/ghostty` does not
currently publish a rendering-capable xcframework). The archive already
contains `ghostty.h` and a module map, so `import GhosttyKit` works.

Bump `GHOSTTYKIT_TAG` in the script to track a newer SHA.

### Stage 2 — generate and open the Xcode project

```bash
xcodegen generate                # reads project.yml → LibghosttyHello.xcodeproj
open LibghosttyHello.xcodeproj
# Build and run in Xcode (⌘R)
```

Expected result: a window showing the libghostty version and build mode.

## Alternative: build the xcframework from source

```bash
./scripts/fetch-ghostty.sh        # pulls ghostty source tarball into vendor/ghostty
./scripts/build-xcframework.sh    # runs zig build; produces vendor/ghostty/zig-out/GhosttyKit.xcframework
```

Currently NOT the recommended path for this POC:
- Zig 0.15.2 installed through Nix lacks darwin libc stubs; build fails with
  `undefined symbol: _fork, _abort, …` even inside `env -i`.
- Official Zig tarballs (https://ziglang.org/download/) work but require
  manual install.

## What this POC validates (in order)

- [x] `GhosttyKit.xcframework` downloads and expands with module map present.
- [x] `ghostty.h` (1208 lines, embedding API) parses with clang.
- [x] SwiftUI app links `GhosttyKit` and calls `ghostty_info()` at runtime.
- [x] `ghostty_app_new` / `ghostty_surface_new` succeed with a real `NSView`.
- [x] PTY attached to the user's shell renders inside the surface; printable
      text plus Enter / Backspace / Tab / Escape / arrows round-trip.

**M-1 passed.** Libghostty is a viable terminal engine for Roost under the
Rust-core + Swift-frontend architecture. Proceed to M0 (walking skeleton).

Remaining POC gaps (deferred to roost-core work, not blockers):
- No IME (`NSTextInputClient` not implemented).
- No key repeat handling.
- No modifier-chord keybindings (`⌘C` / `⌘V` pass-through).
- No resize-driven font re-layout polish.
- `wakeup_cb` currently relies on ghostty calling it; no display-link tick
  fallback.

## Pinning

`scripts/fetch-prebuilt-xcframework.sh` pins via `GHOSTTYKIT_TAG`
(default `xcframework-e36dd9d5…29516`). See
https://github.com/manaflow-ai/ghostty/releases for other tags.
