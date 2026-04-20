#!/usr/bin/env bash
# Build roost-bridge (Rust staticlib) and stage generated Swift/C bindings for
# Xcode to consume. Run from anywhere; paths are resolved from the script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$POC_DIR/../.." && pwd)"
CRATE_DIR="$REPO_ROOT/crates/roost-bridge"
CRATE_NAME="roost-bridge"

PROFILE="${CARGO_PROFILE:-release}"
TARGET_DIR="$REPO_ROOT/target/$PROFILE"
OUT_DIR_PATTERN="$REPO_ROOT/target/$PROFILE/build/${CRATE_NAME}-*/out"

GEN_DIR="$POC_DIR/Generated"

echo "[build-rust] cargo build (profile=$PROFILE)"
(
    cd "$REPO_ROOT"
    if [ "$PROFILE" = "release" ]; then
        cargo build --release -p "$CRATE_NAME"
    else
        cargo build -p "$CRATE_NAME"
    fi
)

STATIC_LIB="$TARGET_DIR/libroost_bridge.a"
if [ ! -f "$STATIC_LIB" ]; then
    echo "[build-rust] missing $STATIC_LIB" >&2
    exit 1
fi

OUT_DIR="$(ls -dt $OUT_DIR_PATTERN 2>/dev/null | head -n1 || true)"
if [ -z "$OUT_DIR" ] || [ ! -d "$OUT_DIR" ]; then
    echo "[build-rust] couldn't find generated-sources dir matching $OUT_DIR_PATTERN" >&2
    exit 1
fi
echo "[build-rust] generated sources in $OUT_DIR"

rm -rf "$GEN_DIR"
mkdir -p "$GEN_DIR"

cp "$STATIC_LIB" "$GEN_DIR/libroost_bridge.a"

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
echo "  Bindings:    $GEN_DIR/RoostBridge.swift (+ SwiftBridgeCore.swift)"
echo "  Bridging H:  $GEN_DIR/RoostBridge-Bridging.h"
