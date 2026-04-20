#!/usr/bin/env bash
# Build roost-bridge (Rust staticlib) and stage generated Swift/C bindings for
# Xcode to consume. Run from anywhere; paths are resolved from the script.
set -euo pipefail

# Xcode's PhaseScript phase runs with a minimal PATH (~/ /usr/bin:/bin:...).
# Prepend the usual cargo install locations so `cargo` resolves.
for p in \
    "$HOME/.cargo/bin" \
    "$HOME/.local/bin" \
    /opt/homebrew/bin \
    /usr/local/bin \
    /run/current-system/sw/bin
do
    case ":$PATH:" in
        *":$p:"*) ;;
        *) [ -d "$p" ] && PATH="$p:$PATH" ;;
    esac
done
export PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$POC_DIR/../.." && pwd)"
CRATE_NAME="roost-bridge"
HOSTD_NAME="roost-hostd"
ATTACH_NAME="roost-attach"

PROFILE="${CARGO_PROFILE:-release}"
TARGET_DIR="$REPO_ROOT/target/$PROFILE"
OUT_GLOB="$REPO_ROOT/target/$PROFILE/build/${CRATE_NAME}-*/out/$CRATE_NAME/$CRATE_NAME.swift"

GEN_DIR="$POC_DIR/Generated"

echo "[build-rust] cargo build (profile=$PROFILE) -p $CRATE_NAME -p $HOSTD_NAME -p $ATTACH_NAME"
(
    cd "$REPO_ROOT"
    if [ "$PROFILE" = "release" ]; then
        cargo build --release -p "$CRATE_NAME" -p "$HOSTD_NAME" -p "$ATTACH_NAME"
    else
        cargo build -p "$CRATE_NAME" -p "$HOSTD_NAME" -p "$ATTACH_NAME"
    fi
)

STATIC_LIB="$TARGET_DIR/libroost_bridge.a"
if [ ! -f "$STATIC_LIB" ]; then
    echo "[build-rust] missing $STATIC_LIB" >&2
    exit 1
fi

HOSTD_BIN="$TARGET_DIR/$HOSTD_NAME"
if [ ! -f "$HOSTD_BIN" ]; then
    echo "[build-rust] missing $HOSTD_BIN" >&2
    exit 1
fi

ATTACH_BIN="$TARGET_DIR/$ATTACH_NAME"
if [ ! -f "$ATTACH_BIN" ]; then
    echo "[build-rust] missing $ATTACH_BIN" >&2
    exit 1
fi

# Pick the OUT_DIR whose generated swift file is freshest. Cargo may leave
# multiple hash-keyed build dirs behind; dir-level mtime doesn't reflect
# whether swift-bridge_build::parse_bridges just rewrote the .swift.
LATEST_SWIFT="$(ls -t $OUT_GLOB 2>/dev/null | head -n1 || true)"
if [ -z "$LATEST_SWIFT" ] || [ ! -f "$LATEST_SWIFT" ]; then
    echo "[build-rust] couldn't find generated $CRATE_NAME.swift matching $OUT_GLOB" >&2
    exit 1
fi
OUT_DIR="$(dirname "$(dirname "$LATEST_SWIFT")")"
echo "[build-rust] generated sources in $OUT_DIR"

rm -rf "$GEN_DIR"
mkdir -p "$GEN_DIR"

cp "$STATIC_LIB" "$GEN_DIR/libroost_bridge.a"
cp "$HOSTD_BIN" "$GEN_DIR/$HOSTD_NAME"
chmod +x "$GEN_DIR/$HOSTD_NAME"
cp "$ATTACH_BIN" "$GEN_DIR/$ATTACH_NAME"
chmod +x "$GEN_DIR/$ATTACH_NAME"

# swift-bridge lays out:
#   $OUT_DIR/SwiftBridgeCore.{swift,h}
#   $OUT_DIR/<crate_name>/<crate_name>.{swift,h}
cp "$OUT_DIR/SwiftBridgeCore.h" "$GEN_DIR/"
cp "$OUT_DIR/SwiftBridgeCore.swift" "$GEN_DIR/"
cp "$OUT_DIR/$CRATE_NAME/$CRATE_NAME.h" "$GEN_DIR/roost_bridge.h"
cp "$OUT_DIR/$CRATE_NAME/$CRATE_NAME.swift" "$GEN_DIR/RoostBridge.swift"

# Swift uses a bridging header (set via SWIFT_OBJC_BRIDGING_HEADER in Xcode)
# to surface the C declarations to Swift. Keep it tiny and check it in.
cat > "$GEN_DIR/RoostBridge-Bridging.h" <<'EOF'
#ifndef ROOST_BRIDGE_BRIDGING_H
#define ROOST_BRIDGE_BRIDGING_H

#import "SwiftBridgeCore.h"
#import "roost_bridge.h"

#endif
EOF

echo "[build-rust] done."
echo "  Static lib:  $GEN_DIR/libroost_bridge.a"
echo "  Hostd bin:   $GEN_DIR/$HOSTD_NAME"
echo "  Attach bin:  $GEN_DIR/$ATTACH_NAME"
echo "  Bindings:    $GEN_DIR/RoostBridge.swift (+ SwiftBridgeCore.swift)"
echo "  Bridging H:  $GEN_DIR/RoostBridge-Bridging.h"
