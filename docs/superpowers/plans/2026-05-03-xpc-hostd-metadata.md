# XPC Hostd Metadata Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional XPC hostd path for session metadata while keeping terminal processes app-owned.

**Architecture:** Extract the existing SQLite-backed hostd actor into a shared `RoostHostdCore` target. Add a `RoostHostdXPCService` executable target and a main-app `XPCHostdClient` adapter behind the existing `RoostHostdClient` protocol. Development runs and missing XPC bundles fall back to `LocalHostdClient`.

**Tech Stack:** Swift 6, SwiftPM, Foundation `NSXPCConnection`, SQLite3, swift-testing, existing Roost hostd models.

---

## Files

- Create: `RoostHostdCore/HostdStorage.swift`
- Create: `RoostHostdCore/RoostHostd.swift`
- Create: `RoostHostdCore/SessionStore.swift`
- Create: `RoostHostdCore/HostdRuntimeOwnership.swift`
- Create: `RoostHostdXPCService/main.swift`
- Create: `RoostHostdCore/HostdXPCProtocol.swift`
- Create: `RoostHostdCore/HostdXPCMessages.swift`
- Create: `RoostHostdXPCService/HostdXPCService.swift`
- Create: `RoostHostdXPCService/Info.plist`
- Create: `Muxy/Services/Hostd/XPCHostdClient.swift`
- Create: `Muxy/Services/Hostd/RoostHostdClientFactory.swift`
- Modify: `Package.swift`
- Modify: `Muxy/MuxyApp.swift`
- Modify: `Muxy/Services/Hostd/RoostHostdClient.swift`
- Modify: `scripts/build-release.sh`
- Test: `Tests/MuxyTests/Hostd/HostdXPCCodecTests.swift`
- Test: `Tests/MuxyTests/Hostd/XPCHostdClientTests.swift`
- Test: `Tests/MuxyTests/Hostd/RoostHostdClientFactoryTests.swift`

## Task 1: Extract Hostd Core

- [x] Move `Muxy/Services/Hostd/HostdStorage.swift`, `RoostHostd.swift`, and `SessionStore.swift` into `RoostHostdCore/`.
- [x] Add `RoostHostdCore/HostdRuntimeOwnership.swift`:

```swift
import Foundation

public enum HostdRuntimeOwnership: String, Sendable, Codable {
    case appOwnedMetadataOnly
    case hostdOwnedProcess
}
```

- [x] Make core types needed by app/tests internal to the module where possible and public only where cross-target access requires it: `RoostHostd`, `HostdStorage`, `SessionStore`.
- [x] Update `Package.swift` so `Roost` and `RoostTests` depend on `RoostHostdCore`.
- [x] Run `swift test --filter Hostd`; expected: existing hostd tests still pass.

## Task 2: Add XPC Messages And Service Adapter

- [x] Add `RoostHostdCore/HostdXPCMessages.swift` with Codable DTOs:

```swift
import Foundation
import MuxyShared

public struct HostdCreateSessionRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public let projectID: UUID
    public let worktreeID: UUID
    public let workspacePath: String
    public let agentKind: AgentKind
    public let command: String?
}

public struct HostdSessionIDRequest: Sendable, Codable, Equatable {
    public let id: UUID
}

public struct HostdXPCReply: Sendable, Codable, Equatable {
    public let ok: Bool
    public let data: Data?
    public let error: String?
}
```

- [x] Add tests proving request and reply round-trip through `JSONEncoder` / `JSONDecoder`.
- [x] Add `RoostHostdCore/HostdXPCProtocol.swift` with `@objc` selector methods using `Data` and completion handlers.
- [x] Add `HostdXPCService` class that decodes requests, calls `RoostHostd`, and encodes replies.
- [x] Verify service adapter by building `RoostHostdXPCService` and covering shared codec + client/factory paths with tests.

## Task 3: Add XPC Client With Injectable Transport

- [x] Add `XPCHostdTransport` protocol in `Muxy/Services/Hostd/XPCHostdClient.swift`.
- [x] Implement `XPCHostdClient` as `RoostHostdClient`.
- [x] `XPCHostdClient.runtimeOwnership()` returns the service-reported ownership.
- [x] Unit test the client with a fake transport that captures requests and returns encoded responses.
- [x] Unit test transport errors propagate as thrown client errors.

## Task 4: Add Client Factory And Launch Routing

- [x] Extend `RoostHostdClient` with:

```swift
func runtimeOwnership() async throws -> HostdRuntimeOwnership
```

- [x] `LocalHostdClient.runtimeOwnership()` returns `.appOwnedMetadataOnly`.
- [x] Add `RoostHostdClientFactory.make()` that tries bundled XPC and falls back to local.
- [x] Update `MuxyApp` startup to use the factory.
- [x] Only call `markAllRunningExited()` when ownership is `.appOwnedMetadataOnly`.
- [x] Add fallback tests with an injected unavailable XPC builder.

## Task 5: Embed XPC Service In Release Bundle

- [x] Add `.executableTarget(name: "RoostHostdXPCService", dependencies: ["MuxyShared", "RoostHostdCore"], path: "RoostHostdXPCService")`.
- [x] Add `RoostHostdXPCService/Info.plist` with bundle id `app.roost.mac.hostd`.
- [x] Update `scripts/build-release.sh` to build the service binary and create `RoostHostdXPCService.xpc`.
- [x] Sign the `.xpc` before signing `Roost.app`.
- [x] Run release packaging and verify `RoostHostdXPCService.xpc` exists in the app bundle and zip.

## Task 6: Verification And Docs

- [x] Run `swift test --filter Hostd`.
- [x] Run `swift build`.
- [x] Run `scripts/checks.sh --fix`.
- [x] Append a short Phase 6 follow-up note to `docs/roost-migration-plan.md` describing XPC metadata path and remaining PTY work.
- [x] Commit with `jj commit -m "feat(hostd): add xpc metadata service path"`.

## Self-Review

- Spec coverage: covers core extraction, XPC message shape, client fallback, runtime ownership, release embedding, tests, and PTY deferral.
- Placeholder scan: no TBD/TODO placeholders.
- Type consistency: `HostdRuntimeOwnership`, `RoostHostdClient`, `XPCHostdClient`, and XPC message DTO names are consistent across tasks.
