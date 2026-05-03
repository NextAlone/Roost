# XPC Hostd Metadata Design

## Goal

Move Roost's hostd metadata API behind an optional XPC service without changing terminal ownership yet. The main app keeps owning Ghostty surfaces, shell processes, and agent terminal panes. The hostd path becomes cross-process for session records only.

## Scope

This design covers A1/A2:

- Build and embed a `RoostHostdXPCService.xpc` bundle.
- Keep the app-facing `RoostHostdClient` protocol as the stable boundary.
- Add an `XPCHostdClient` that implements the existing client protocol.
- Reuse the existing SQLite-backed `RoostHostd` logic from both the app fallback and the XPC service.
- Preserve local fallback for `swift run Roost` and any app bundle that does not contain the XPC service.
- Add a runtime ownership value so later PTY migration can switch behavior without redefining the current API.

This design does not move PTY ownership, terminal rendering, stdin/stdout streaming, resize events, signals, or reattach behavior.

## Architecture

The implementation splits hostd into three layers:

1. `RoostHostdCore` contains `HostdStorage`, `SessionStore`, and `RoostHostd`. It has no SwiftUI, AppKit, Ghostty, or main app dependencies. Both the app and XPC executable can use it.
2. `RoostHostdXPCService` hosts an `NSXPCListener.service()` and exports a protocol object. The service owns a `RoostHostd` actor and handles metadata requests.
3. The main app creates a `RoostHostdClient` through a factory. Bundled apps try `XPCHostdClient` first. Development runs and failures fall back to `LocalHostdClient`.

The app-facing client protocol remains Swift-native and async. XPC details stay inside the adapter.

## XPC Message Shape

XPC methods exchange `Data` envelopes rather than exposing Swift structs as `NSSecureCoding` classes. Requests and replies use `Codable` structs:

- `HostdCreateSessionRequest`
- `HostdSessionIDRequest`
- `HostdXPCReply`
- `[SessionRecord]`

This keeps `SessionRecord` as the canonical shared DTO and avoids a parallel class hierarchy. It also lets future protocol versions add fields without changing every XPC selector.

## Runtime Ownership

Add:

```swift
enum HostdRuntimeOwnership: String, Sendable, Codable {
    case appOwnedMetadataOnly
    case hostdOwnedProcess
}
```

A1/A2 always reports `.appOwnedMetadataOnly`. The main app should keep calling `markAllRunningExited()` on launch in that mode, because running records still describe app-owned terminal processes. When B migrates PTY ownership, the XPC service will report `.hostdOwnedProcess` and launch cleanup will stop marking live sessions exited.

## Fallback Behavior

The factory should prefer XPC only when a bundled XPC service is present. If connection setup fails, the app should use `LocalHostdClient`. XPC failure must not block app launch or terminal creation.

Errors from individual hostd operations should still be thrown through `RoostHostdClient` and handled by existing best-effort call sites. History UI can surface reload failures through its existing store state.

## Release Packaging

`Package.swift` gains a separate executable target for `RoostHostdXPCService`. `scripts/build-release.sh` builds it and embeds it under:

```text
Roost.app/Contents/XPCServices/RoostHostdXPCService.xpc
```

The `.xpc` bundle gets its own `Info.plist` with `CFBundlePackageType = XPC!`. Signing order is service first, app second.

## Testing

Test the feature without requiring a live XPC service:

- Codable message round trips for request/reply DTOs.
- Direct service adapter tests against a temporary SQLite database.
- `XPCHostdClient` tests using an injected transport/fake proxy.
- Factory tests for fallback when XPC is unavailable.
- Release script syntax validation with `bash -n`.

The full packaged XPC smoke can be manual for this slice because SwiftPM does not run a bundled app in tests.

## PTY Migration Compatibility

Future PTY work can reuse this boundary by adding methods instead of replacing it:

- `attachSession`
- `releaseSession`
- `terminateSession`
- `resizeSession`
- `sendInput`

The existing `createSession` can evolve from metadata insertion to process creation once `HostdRuntimeOwnership.hostdOwnedProcess` is active. Until then it remains metadata-only.

## Exit Criteria

- App launch uses XPC hostd when bundled and falls back locally when not bundled.
- Existing session history behavior is unchanged from the user's perspective.
- `scripts/build-release.sh` produces a bundle layout that includes the XPC service.
- `scripts/checks.sh --fix` passes.
