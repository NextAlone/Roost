#!/usr/bin/env bash
# Build GhosttyKit.xcframework from vendored ghostty source.
# Requires zig >= 0.15.2 on PATH (install via nix, asdf, etc.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$POC_DIR/../.." && pwd)"
GHOSTTY_DIR="$REPO_ROOT/vendor/ghostty"
OUT_FRAMEWORK="$GHOSTTY_DIR/zig-out/GhosttyKit.xcframework"

if [ ! -d "$GHOSTTY_DIR" ]; then
    echo "[build-xcframework] Missing $GHOSTTY_DIR. Run scripts/fetch-ghostty.sh first." >&2
    exit 1
fi

if ! command -v zig >/dev/null 2>&1; then
    echo "[build-xcframework] zig not found on PATH. Install zig >= 0.15.2 (try 'nix shell nixpkgs#zig_0_15')." >&2
    exit 1
fi

ZIG_VERSION="$(zig version)"
echo "[build-xcframework] zig $ZIG_VERSION"

# On darwin zig needs libSystem / Apple SDK. When running from a bare nix shell
# the SDK path is not exported, which breaks linking (undefined _fork, _abort...).
# Export SDKROOT from xcrun if xcode-select points at an SDK.
if ! [[ "${SDKROOT:-}" ]] && command -v xcrun >/dev/null 2>&1; then
    if SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null)"; then
        export SDKROOT="$SDK_PATH"
        echo "[build-xcframework] SDKROOT=$SDKROOT"
    fi
fi
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"

OPTIMIZE="${OPTIMIZE:-ReleaseFast}"
echo "[build-xcframework] Building (optimize=$OPTIMIZE) — first build may take several minutes."
cd "$GHOSTTY_DIR"

# Nix-shell injects NIX_LDFLAGS / NIX_CFLAGS_* which corrupt zig's linker
# (ghostty's own build.nu uses `env -i` for the same reason before xcodebuild).
# We relaunch zig with a sanitized environment: keep only PATH, HOME, SDKROOT,
# MACOSX_DEPLOYMENT_TARGET, TERM and the zig cache override.
ZIG_BIN="$(command -v zig)"
env -i \
    HOME="$HOME" \
    PATH="$PATH" \
    TERM="${TERM:-xterm}" \
    SDKROOT="$SDKROOT" \
    MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
    "$ZIG_BIN" build \
        -Doptimize="$OPTIMIZE" \
        -Demit-xcframework=true \
        -Demit-macos-app=false

if [ ! -d "$OUT_FRAMEWORK" ]; then
    echo "[build-xcframework] Build completed but $OUT_FRAMEWORK is missing." >&2
    echo "  Check zig-out/ contents." >&2
    ls -la "$GHOSTTY_DIR/zig-out" >&2 || true
    exit 1
fi

echo "[build-xcframework] Success."
echo "  $OUT_FRAMEWORK"
