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

OPTIMIZE="${OPTIMIZE:-ReleaseFast}"
echo "[build-xcframework] Building (optimize=$OPTIMIZE) — first build may take several minutes."
cd "$GHOSTTY_DIR"

# -Demit-xcframework=true : produce GhosttyKit.xcframework under zig-out/
# -Demit-macos-app=false  : skip the Swift/Xcode app build
zig build \
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
