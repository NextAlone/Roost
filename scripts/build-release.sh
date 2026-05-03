#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"

ARCH=""
VERSION=""
SIGN_IDENTITY=""
SPARKLE_PUBLIC_KEY=""
SPARKLE_FEED_URL=""
PACKAGE_FORMAT="zip"
BUILD_NUMBER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --sign-identity)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --sparkle-public-key)
            SPARKLE_PUBLIC_KEY="$2"
            shift 2
            ;;
        --sparkle-feed-url)
            SPARKLE_FEED_URL="$2"
            shift 2
            ;;
        --zip)
            PACKAGE_FORMAT="zip"
            shift
            ;;
        --dmg)
            PACKAGE_FORMAT="dmg"
            shift
            ;;
        --build-number)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$ARCH" || -z "$VERSION" ]]; then
    echo "Usage: $0 --arch <arm64|x86_64> --version <X.Y.Z> [--zip|--dmg] [--build-number <number>] [--sign-identity <identity>] [--sparkle-public-key <key>] [--sparkle-feed-url <url>]"
    exit 1
fi

if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
    echo "Error: arch must be arm64 or x86_64"
    exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version must be in X.Y.Z format"
    exit 1
fi

TRIPLE="${ARCH}-apple-macosx14.0"
if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
fi

APP_BUNDLE="$BUILD_DIR/Roost.app"
ZIP_NAME="Roost-${VERSION}-${ARCH}.zip"
DMG_NAME="Roost-${VERSION}-${ARCH}.dmg"

rm -rf "$APP_BUNDLE"

echo "==> Building for $ARCH ($TRIPLE)"
cd "$PROJECT_ROOT"
swift build -c release --triple "$TRIPLE"
swift build -c release --triple "$TRIPLE" --product RoostHostdXPCService
swift build -c release --triple "$TRIPLE" --product roost-hostd-attach
swift build -c release --triple "$TRIPLE" --product roost-hostd-daemon

SPM_BUILD_DIR=$(swift build -c release --triple "$TRIPLE" --show-bin-path)

echo "==> Creating app bundle"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$SPM_BUILD_DIR/Roost" "$APP_BUNDLE/Contents/MacOS/Roost"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/Roost"
cp "$SPM_BUILD_DIR/roost-hostd-attach" "$APP_BUNDLE/Contents/MacOS/roost-hostd-attach"
chmod 755 "$APP_BUNDLE/Contents/MacOS/roost-hostd-attach"
cp "$SPM_BUILD_DIR/roost-hostd-daemon" "$APP_BUNDLE/Contents/MacOS/roost-hostd-daemon"
chmod 755 "$APP_BUNDLE/Contents/MacOS/roost-hostd-daemon"

echo "==> Stripping local and debug symbols"
strip -Sx "$APP_BUNDLE/Contents/MacOS/Roost"
strip -Sx "$APP_BUNDLE/Contents/MacOS/roost-hostd-attach"
strip -Sx "$APP_BUNDLE/Contents/MacOS/roost-hostd-daemon"

if [[ -d "$SPM_BUILD_DIR/Roost_Roost.bundle" ]]; then
    cp -R "$SPM_BUILD_DIR/Roost_Roost.bundle" "$APP_BUNDLE/Contents/Resources/Roost_Roost.bundle"
elif [[ -d "$SPM_BUILD_DIR/Muxy_Muxy.bundle" ]]; then
    cp -R "$SPM_BUILD_DIR/Muxy_Muxy.bundle" "$APP_BUNDLE/Contents/Resources/Muxy_Muxy.bundle"
fi

echo "==> Embedding hostd XPC service"
XPC_BUNDLE="$APP_BUNDLE/Contents/XPCServices/RoostHostdXPCService.xpc"
mkdir -p "$XPC_BUNDLE/Contents/MacOS"
cp "$SPM_BUILD_DIR/RoostHostdXPCService" "$XPC_BUNDLE/Contents/MacOS/RoostHostdXPCService"
cp "$PROJECT_ROOT/RoostHostdXPCService/Info.plist" "$XPC_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$XPC_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$XPC_BUNDLE/Contents/Info.plist"
strip -Sx "$XPC_BUNDLE/Contents/MacOS/RoostHostdXPCService"

cp "$PROJECT_ROOT/Muxy/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

echo "==> Compiling app icons"
ICON_BUILD_DIR="$BUILD_DIR/AppIcons"
ICON_PARTIAL_PLIST="$BUILD_DIR/AppIcon-Partial.plist"
"$SCRIPT_DIR/compile-app-icons.sh" "$ICON_BUILD_DIR" Graphite "$ICON_PARTIAL_PLIST" > /dev/null
cp "$ICON_BUILD_DIR/Assets.car" "$APP_BUNDLE/Contents/Resources/Assets.car"
cp "$ICON_BUILD_DIR/Graphite.icns" "$APP_BUNDLE/Contents/Resources/Graphite.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile Graphite" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string Graphite" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIconName Graphite" "$APP_BUNDLE/Contents/Info.plist"

echo "==> Embedding Sparkle.framework"
SPARKLE_FRAMEWORK="$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Error: Sparkle.framework not found at $SPARKLE_FRAMEWORK"
    exit 1
fi
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
    echo "==> Injecting Sparkle keys into Info.plist"
    APP_PLIST="$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$APP_PLIST"
    if [[ -n "$SPARKLE_FEED_URL" ]]; then
        /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$APP_PLIST"
    fi
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
    SPARKLE_DIR="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

    echo "==> Signing Sparkle.framework (inside-out)"
    /usr/bin/codesign --force --options runtime --preserve-metadata=entitlements \
        --sign "$SIGN_IDENTITY" \
        "$SPARKLE_DIR/Versions/B/XPCServices/Installer.xpc"

    /usr/bin/codesign --force --options runtime --preserve-metadata=entitlements \
        --sign "$SIGN_IDENTITY" \
        "$SPARKLE_DIR/Versions/B/XPCServices/Downloader.xpc"

    /usr/bin/codesign --force --options runtime --preserve-metadata=entitlements \
        --sign "$SIGN_IDENTITY" \
        "$SPARKLE_DIR/Versions/B/Updater.app"

    /usr/bin/codesign --force --options runtime --preserve-metadata=entitlements \
        --sign "$SIGN_IDENTITY" \
        "$SPARKLE_DIR/Versions/B/Autoupdate"

    /usr/bin/codesign --force --options runtime \
        --sign "$SIGN_IDENTITY" \
        "$SPARKLE_DIR"

    echo "==> Signing hostd XPC service"
    /usr/bin/codesign --force --options runtime \
        --sign "$SIGN_IDENTITY" \
        "$XPC_BUNDLE"

    echo "==> Signing hostd attach helper"
    /usr/bin/codesign --force --options runtime \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE/Contents/MacOS/roost-hostd-attach"

    echo "==> Signing hostd daemon"
    /usr/bin/codesign --force --options runtime \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE/Contents/MacOS/roost-hostd-daemon"

    echo "==> Signing app bundle"
    /usr/bin/codesign --force --options runtime \
        --entitlements "$PROJECT_ROOT/Muxy/Muxy.entitlements" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE"
fi

if [[ "$PACKAGE_FORMAT" == "zip" ]]; then
    echo "==> Creating ZIP"
    cd "$BUILD_DIR"
    rm -f "$ZIP_NAME" SHA256SUMS.txt
    /usr/bin/ditto -c -k --keepParent "Roost.app" "$ZIP_NAME"
    shasum -a 256 "$ZIP_NAME" > SHA256SUMS.txt
    echo "==> Done: $BUILD_DIR/$ZIP_NAME"
    echo "==> Checksum: $BUILD_DIR/SHA256SUMS.txt"
    exit 0
fi

if [[ "$PACKAGE_FORMAT" != "dmg" ]]; then
    echo "Error: package format must be zip or dmg"
    exit 1
fi

echo "==> Creating DMG"
if ! command -v create-dmg &> /dev/null; then
    echo "Error: create-dmg not found. Install with: npm install --global create-dmg"
    exit 1
fi

cd "$BUILD_DIR"
create-dmg "$APP_BUNDLE" "$BUILD_DIR" || true

GENERATED_DMG=$(find "$BUILD_DIR" -maxdepth 1 -name "Roost*.dmg" -not -name "$DMG_NAME" | head -1)
if [[ -n "$GENERATED_DMG" ]]; then
    mv "$GENERATED_DMG" "$BUILD_DIR/$DMG_NAME"
fi

if [[ -n "$SIGN_IDENTITY" && -f "$BUILD_DIR/$DMG_NAME" ]]; then
    echo "==> Signing DMG"
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$BUILD_DIR/$DMG_NAME"
fi

echo "==> Done: $BUILD_DIR/$DMG_NAME"
