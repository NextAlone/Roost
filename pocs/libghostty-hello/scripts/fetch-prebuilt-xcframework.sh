#!/usr/bin/env bash
# Fetch a prebuilt GhosttyKit.xcframework from manaflow-ai/ghostty releases.
# Upstream ghostty-org/ghostty currently does not publish GhosttyKit.xcframework
# directly (Ghostty.app is statically linked; the release ships a VT-only
# xcframework). The cmux project publishes full xcframework builds keyed by
# ghostty commit SHA; we piggyback on those for the POC.
#
# Alternative: scripts/build-xcframework.sh (builds from source via zig).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$POC_DIR/../.." && pwd)"
VENDOR_DIR="$REPO_ROOT/vendor"
OUT_DIR="$VENDOR_DIR/GhosttyKit.xcframework"

# Pinned tag. Bump manually after verifying a newer xcframework works.
# See: https://github.com/manaflow-ai/ghostty/releases
TAG="${GHOSTTYKIT_TAG:-xcframework-e36dd9d50287736cd863e159ef50534364c29516}"
ARCHIVE_URL="https://github.com/manaflow-ai/ghostty/releases/download/${TAG}/GhosttyKit.xcframework.tar.gz"

mkdir -p "$VENDOR_DIR"
SHA="${TAG#xcframework-}"

if [ -d "$OUT_DIR" ]; then
    echo "[fetch-prebuilt] $OUT_DIR already exists; delete it to re-fetch."
    exit 0
fi

echo "[fetch-prebuilt] Downloading $ARCHIVE_URL"
TMP_TAR="$(mktemp -t ghosttykit.XXXXXX.tar.gz)"
trap 'rm -f "$TMP_TAR"' EXIT
curl -fsSL --retry 3 "$ARCHIVE_URL" -o "$TMP_TAR"

echo "[fetch-prebuilt] Extracting to $VENDOR_DIR"
tar -xzf "$TMP_TAR" -C "$VENDOR_DIR"

if [ ! -d "$OUT_DIR" ]; then
    echo "[fetch-prebuilt] Archive extracted but $OUT_DIR missing." >&2
    ls -la "$VENDOR_DIR" >&2
    exit 1
fi

# The archive already bundles ghostty.h and module.modulemap under
# <slice>/Headers/, so Swift can `import GhosttyKit` out of the box.
echo "[fetch-prebuilt] Done."
echo "  Framework: $OUT_DIR"
echo "  Tag:       $TAG"
echo "  SHA:       $SHA"
