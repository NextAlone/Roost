#!/usr/bin/env bash
# Fetch ghostty source into ../../vendor/ghostty at a pinned revision.
# Uses tarball download instead of `git clone` (lighter + no git history needed).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$POC_DIR/../.." && pwd)"
VENDOR_DIR="$REPO_ROOT/vendor"
GHOSTTY_DIR="$VENDOR_DIR/ghostty"

# Track ghostty-org/ghostty `main` for initial POC. Bump after M-1 validates.
GHOSTTY_REV="${GHOSTTY_REV:-main}"
GHOSTTY_URL="https://github.com/ghostty-org/ghostty/archive/${GHOSTTY_REV}.tar.gz"

mkdir -p "$VENDOR_DIR"

if [ -d "$GHOSTTY_DIR" ]; then
    echo "[fetch-ghostty] $GHOSTTY_DIR already exists; delete it to re-fetch."
    exit 0
fi

echo "[fetch-ghostty] Downloading $GHOSTTY_URL"
TMP_TAR="$(mktemp -t ghostty.XXXXXX.tar.gz)"
trap 'rm -f "$TMP_TAR"' EXIT
curl -fsSL "$GHOSTTY_URL" -o "$TMP_TAR"

echo "[fetch-ghostty] Extracting to $GHOSTTY_DIR"
mkdir -p "$GHOSTTY_DIR"
tar -xzf "$TMP_TAR" -C "$GHOSTTY_DIR" --strip-components=1

echo "[fetch-ghostty] Done."
echo "  Source: $GHOSTTY_DIR"
echo "  Next:   $SCRIPT_DIR/build-xcframework.sh"
