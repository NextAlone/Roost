# Release Distribution

Roost currently has three distribution paths:

- GitHub Releases: `Roost-<version>-arm64.zip` plus `SHA256SUMS.txt`.
- Nix flakes: `github:NextAlone/Roost` and `github:NextAlone/Roost/v<version>` expose the `aarch64-darwin` package and nix-darwin module.
- Sparkle: code and scripts are present, but no public update feed is enabled by default.

## Current ZIP Release

Run the first-party GitHub Actions workflow from `main`. **The workflow handles both the GitHub Release and the Nix package bump in one run** — do not bump the Nix hash by hand.

1. Open **Actions > Release > Run workflow**.
2. Set `version` to the release version (`X.Y.Z`, no `v` prefix, no `-beta.N`).
3. Leave `build_number` empty to use the GitHub run number, or provide a numeric build number.
4. Leave `draft` disabled for a publishable release.

What the workflow does, in order:

1. Builds the self-signed/ad-hoc ZIP via `scripts/build-release.sh --sign-identity -`.
2. Computes the ZIP SHA256 and the Nix SRI hash (`sha256-…` base64).
3. Runs `scripts/update-release-metadata.sh <version> <nix-hash>`, which rewrites:
   - `nix/package.nix` — `version` and `src.hash`.
   - `Muxy/Info.plist`, `RoostHostdXPCService/Info.plist` — `CFBundleShortVersionString`.
   - `docs/nix-darwin.md` — `github:NextAlone/Roost/v<version>` flake refs.
   - `docs/release-distribution.md`, `RELEASE-CHECKLIST.md` — version strings, ZIP filename, `--version` flags.
4. Commits the bumped files as `chore(release): prepare v<version>` and pushes to the triggering branch.
5. Tags `v<version>` at that commit and creates the GitHub Release with `Roost-<version>-arm64.zip` plus `SHA256SUMS.txt`. The release notes embed the commit SHA, the ZIP SHA256, and the Nix SRI hash.

After the workflow finishes, verify the Nix flake at the new tag (it pulls the published ZIP and re-checks the hash):

```bash
nix --extra-experimental-features 'nix-command flakes' build \
  github:NextAlone/Roost/v<version>#packages.aarch64-darwin.default \
  --refresh --no-link
```

The self-signed/ad-hoc archive is not Developer ID signed and is not notarized.

### Manual Nix Hash Bump

Only needed if a release ZIP is replaced out-of-band or `nix/package.nix` drifts from the published asset. Run from the repo root:

```bash
ZIP="Roost-<version>-arm64.zip"
gh release download "v<version>" --repo NextAlone/Roost --pattern "$ZIP" --dir /tmp
NIX_HASH="sha256-$(openssl dgst -sha256 -binary "/tmp/$ZIP" | openssl base64 -A)"
scripts/update-release-metadata.sh "<version>" "$NIX_HASH"
```

Then commit the resulting changes (same set the workflow touches) on a normal PR.

## Local Test Build

For local sanity checks (e.g. handing a teammate a build), always pass `--sign-identity -` to ad-hoc sign the bundle:

```bash
scripts/build-release.sh --arch arm64 --version <X.Y.Z[-beta.N]> --zip --sign-identity -
```

Without `--sign-identity`, `swift build` only stamps each binary with a linker ad-hoc signature; the app bundle itself is left with `Sealed Resources=none`, no entitlements bound, and no hardened runtime. The Sparkle framework, hostd XPC service, hostd daemon, and the bundle all need the inside-out re-sign that the script performs when an identity is provided. Use `-` for ad-hoc; substitute a Developer ID identity once notarization credentials exist.

Use a version that does not collide with a published release (e.g. `1.2.2-beta.0`) so the artifact under `build/` does not clobber a real release ZIP. Recipients on macOS still need to clear quarantine on first launch:

```bash
xattr -dr com.apple.quarantine /Applications/Roost.app
```

## Nix

`nix/package.nix` is a `stdenvNoCC.mkDerivation` that fetches the published GitHub release ZIP by `version` and validates it with the SRI hash in `src.hash`. The release workflow rewrites both fields (see "Current ZIP Release" above), so the flake at `github:NextAlone/Roost/v<version>` is consumable as soon as the release is created. See `docs/nix-darwin.md` for the nix-darwin module wiring.

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
  --version 1.1.0 \
  --zip \
  --sign-identity - \
  --sparkle-public-key "$PUBLIC_KEY" \
  --sparkle-feed-url "https://example.com/roost/appcast.xml"
```

Generate an appcast entry for the ZIP:

```bash
SPARKLE_PRIVATE_KEY="$SPARKLE_PRIVATE_KEY" \
  scripts/generate-appcast.sh \
  build/Roost-1.1.0-arm64.zip \
  v1.1.0 \
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
