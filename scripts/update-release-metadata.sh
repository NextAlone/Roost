#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="${ROOST_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <version> <nix-sri-hash>" >&2
    exit 1
fi

VERSION="$1"
NIX_HASH="$2"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version must be in X.Y.Z format" >&2
    exit 1
fi

if ! [[ "$NIX_HASH" =~ ^sha256-[A-Za-z0-9+/]+={0,2}$ ]]; then
    echo "Error: Nix hash must be an SRI sha256 hash" >&2
    exit 1
fi

require_file() {
    if [[ ! -f "$PROJECT_ROOT/$1" ]]; then
        echo "Error: missing $1" >&2
        exit 1
    fi
}

require_file "Muxy/Info.plist"
require_file "RoostHostdXPCService/Info.plist"
require_file "nix/package.nix"
require_file "docs/nix-darwin.md"
require_file "docs/release-distribution.md"
require_file "RELEASE-CHECKLIST.md"

VERSION="$VERSION" NIX_HASH="$NIX_HASH" perl -0pi -e '
    s/version = "[0-9]+\.[0-9]+\.[0-9]+"/version = "$ENV{VERSION}"/g;
    s/hash = "sha256-[^"]+"/hash = "$ENV{NIX_HASH}"/g;
' "$PROJECT_ROOT/nix/package.nix"

VERSION="$VERSION" perl -0pi -e '
    s/(<key>CFBundleShortVersionString<\/key>\s*<string>)[^<]+(<\/string>)/$1$ENV{VERSION}$2/g;
' "$PROJECT_ROOT/Muxy/Info.plist" "$PROJECT_ROOT/RoostHostdXPCService/Info.plist"

VERSION="$VERSION" perl -0pi -e '
    s/github:NextAlone\/Roost\/v[0-9]+\.[0-9]+\.[0-9]+/github:NextAlone\/Roost\/v$ENV{VERSION}/g;
' "$PROJECT_ROOT/docs/nix-darwin.md"

VERSION="$VERSION" perl -0pi -e '
    s/Roost-[0-9]+\.[0-9]+\.[0-9]+-arm64\.zip/Roost-$ENV{VERSION}-arm64.zip/g;
    s/v[0-9]+\.[0-9]+\.[0-9]+/v$ENV{VERSION}/g;
    s/--version [0-9]+\.[0-9]+\.[0-9]+/--version $ENV{VERSION}/g;
    s/Current Release: [0-9]+\.[0-9]+\.[0-9]+/Current Release: $ENV{VERSION}/g;
' "$PROJECT_ROOT/docs/release-distribution.md" "$PROJECT_ROOT/RELEASE-CHECKLIST.md"
