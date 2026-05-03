# Release Distribution

Roost currently has three distribution paths:

- GitHub Releases: `Roost-<version>-arm64.zip` plus `SHA256SUMS.txt`.
- Nix flakes: `github:NextAlone/Roost` and `github:NextAlone/Roost/v<version>` expose the `aarch64-darwin` package and nix-darwin module.
- Sparkle: code and scripts are present, but no public update feed is enabled by default.

## Current ZIP Release

Build the first-party archive with:

```bash
scripts/build-release.sh \
  --arch arm64 \
  --version 1.0.0 \
  --zip \
  --sign-identity -
```

The self-signed/ad-hoc archive is not Developer ID signed and is not notarized. Keep publishing `SHA256SUMS.txt` next to the ZIP.

## Nix

The Nix package fetches the GitHub release ZIP by version and validates it with a fixed-output hash. After uploading or replacing a release asset, update `nix/package.nix` and verify both refs:

```bash
nix --extra-experimental-features 'nix-command flakes' build .#packages.aarch64-darwin.default --no-link
nix --extra-experimental-features 'nix-command flakes' build github:NextAlone/Roost/v1.0.0#packages.aarch64-darwin.default --refresh --no-link
```

## Sparkle Appcast

Sparkle is opt-in until there is a stable hosted feed URL. Do not enable `SUFeedURL` or `SUPublicEDKey` for the default manual release unless the feed is actually published.

Generate a private key once and store it outside the repo:

```bash
scripts/generate-sparkle-key.swift
```

Build an update-enabled app by injecting the derived public key and feed URL:

```bash
PUBLIC_KEY="$(scripts/derive-sparkle-public-key.swift "$SPARKLE_PRIVATE_KEY")"
scripts/build-release.sh \
  --arch arm64 \
  --version 1.0.0 \
  --zip \
  --sign-identity - \
  --sparkle-public-key "$PUBLIC_KEY" \
  --sparkle-feed-url "https://example.com/roost/appcast.xml"
```

Generate an appcast entry for the ZIP:

```bash
SPARKLE_PRIVATE_KEY="$SPARKLE_PRIVATE_KEY" \
  scripts/generate-appcast.sh \
  build/Roost-1.0.0-arm64.zip \
  v1.0.0 \
  1 \
  build/appcast.xml
```

Publish the appcast XML at the same stable URL embedded in the app. A versioned GitHub release asset URL is not enough for automatic updates because clients need one feed URL that keeps moving to the latest release.

## Homebrew

Homebrew distribution remains a separate decision. The cask should point to the GitHub release ZIP, validate its SHA256, and should not be submitted until the preferred trust model is clear:

- Self-signed/ad-hoc cask for power users.
- Developer ID notarized cask for broader public distribution.

## Developer ID

Developer ID notarization is blocked on Apple Developer credentials and should stay separate from the self-signed release workflow. When credentials exist, add:

- Developer ID Application signing identity.
- Hardened Runtime release signing.
- `notarytool` submission in CI.
- Stapling before ZIP packaging.
