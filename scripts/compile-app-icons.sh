#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$PROJECT_ROOT/Muxy/Resources/AppIcons"
OUTPUT_DIR="${1:-$PROJECT_ROOT/build/AppIcons}"
PRIMARY_ICON="${2:-Graphite}"
PARTIAL_PLIST="${3:-$OUTPUT_DIR/AppIcon-Partial.plist}"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

ICON_ARGS=()
ALTERNATE_ARGS=()

for ICON_PATH in "$SOURCE_DIR"/*.icon; do
    ICON_NAME="$(basename "$ICON_PATH" .icon)"
    ICON_ARGS+=("$ICON_PATH")
    if [[ "$ICON_NAME" != "$PRIMARY_ICON" ]]; then
        ALTERNATE_ARGS+=(--alternate-app-icon "$ICON_NAME")
    fi
done

xcrun actool \
    --compile "$OUTPUT_DIR" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon "$PRIMARY_ICON" \
    "${ALTERNATE_ARGS[@]}" \
    --output-partial-info-plist "$PARTIAL_PLIST" \
    "${ICON_ARGS[@]}"

PREVIEW_DIR="$SOURCE_DIR/Previews"
rm -rf "$PREVIEW_DIR"
mkdir -p "$PREVIEW_DIR"

for ICON_PATH in "$SOURCE_DIR"/*.icon; do
    ICON_NAME="$(basename "$ICON_PATH" .icon)"
    TEMP_DIR="$(mktemp -d)"
    TEMP_OUT="$TEMP_DIR/out"
    TEMP_PARTIAL="$TEMP_DIR/partial.plist"
    TEMP_ICONSET="$TEMP_DIR/$ICON_NAME.iconset"
    mkdir -p "$TEMP_OUT"

    xcrun actool \
        --compile "$TEMP_OUT" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon "$ICON_NAME" \
        --output-partial-info-plist "$TEMP_PARTIAL" \
        "$ICON_PATH" > /dev/null

    iconutil -c iconset "$TEMP_OUT/$ICON_NAME.icns" -o "$TEMP_ICONSET"
    cp "$TEMP_ICONSET/icon_128x128@2x.png" "$PREVIEW_DIR/$ICON_NAME.png"
    rm -rf "$TEMP_DIR"
done
