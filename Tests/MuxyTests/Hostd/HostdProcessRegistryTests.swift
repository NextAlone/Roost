import Foundation
import MuxyShared
import RoostHostdCore
import Testing

@testable import RoostHostdCore

@Suite("HostdProcessRegistry")
struct HostdProcessRegistryTests {
    private func makeTempStoreURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-tests")
            .appendingPathComponent(UUID().uuidString)
        return tmp.appendingPathComponent("sessions.sqlite")
    }

    @Test("launch owns a PTY-backed process and terminate marks it exited")
    func launchAndTerminatePTYSession() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let registry = HostdProcessRegistry(store: store)
        let id = UUID()

        let attached = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .terminal,
            command: "printf hostd-ready; sleep 5",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        #expect(attached.record.id == id)
        #expect(attached.ownership == .hostdOwnedProcess)

        let output = try await registry.readAvailableOutput(id: id, timeout: 1)
        let text = String(decoding: output, as: UTF8.self)
        #expect(text.contains("hostd-ready"))

        let reattached = try await registry.attachSession(id: id)
        #expect(reattached.record.id == id)
        #expect(reattached.ownership == .hostdOwnedProcess)
        #expect(reattached.attachedClientCount == 1)

        try await registry.terminateSession(id: id)
        let records = try await store.list()
        #expect(records.first?.id == id)
        #expect(records.first?.lastState == .exited)
    }

    @Test("launched PTY session has a controlling terminal")
    func launchedPTYSessionHasControllingTerminal() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let registry = HostdProcessRegistry(store: store)
        let id = UUID()

        _ = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .terminal,
            command: "if true </dev/tty; then printf controlling-tty; else printf missing-tty; fi; sleep 5",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let text = try await readText(
            from: registry,
            id: id,
            until: { $0.contains("controlling-tty") || $0.contains("missing-tty") }
        )
        #expect(text.contains("controlling-tty"))

        try await registry.terminateSession(id: id)
    }

    @Test("launched PTY session starts with a usable window size")
    func launchedPTYSessionStartsWithUsableWindowSize() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let registry = HostdProcessRegistry(store: store)
        let id = UUID()

        _ = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .terminal,
            command: "stty size; sleep 5",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let text = try await readText(
            from: registry,
            id: id,
            until: { $0.contains("40 120") || $0.contains("0 0") }
        )
        #expect(text.contains("40 120"))

        try await registry.terminateSession(id: id)
    }

    @Test("attach count increments and release decrements")
    func attachCountIncrementsAndReleaseDecrements() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let registry = HostdProcessRegistry(store: store)
        let id = UUID()

        _ = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .terminal,
            command: "sleep 5",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let firstAttach = try await registry.attachSession(id: id)
        let secondAttach = try await registry.attachSession(id: id)
        try await registry.releaseSession(id: id)
        let thirdAttach = try await registry.attachSession(id: id)

        #expect(firstAttach.attachedClientCount == 1)
        #expect(secondAttach.attachedClientCount == 2)
        #expect(thirdAttach.attachedClientCount == 2)

        try await registry.terminateSession(id: id)
    }

    @Test("release without an active attach fails")
    func releaseWithoutActiveAttachFails() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let registry = HostdProcessRegistry(store: store)
        let id = UUID()

        _ = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .terminal,
            command: "sleep 5",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        await #expect(throws: HostdProcessRegistryError.self) {
            try await registry.releaseSession(id: id)
        }

        try await registry.terminateSession(id: id)
    }

    @Test("keepalive is retained until explicit termination")
    func keepaliveIsRetainedUntilExplicitTermination() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let keepalive = RecordingHostdProcessKeepalive()
        let registry = HostdProcessRegistry(store: store, keepalive: keepalive)
        let id = UUID()

        _ = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .terminal,
            command: "sleep 5",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        #expect(keepalive.snapshot == .init(retains: 1, releases: 0, active: 1))

        try await registry.terminateSession(id: id)

        #expect(keepalive.snapshot == .init(retains: 1, releases: 1, active: 0))
    }

    @Test("list live sessions ignores stale persisted records")
    func listLiveSessionsIgnoresStalePersistedRecords() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let id = UUID()
        try await store.record(SessionRecord(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .codex,
            command: "codex",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastState: .running
        ))
        let registry = HostdProcessRegistry(store: store)

        let live = try await registry.listLiveSessions()
        let records = try await store.list()

        #expect(live.isEmpty)
        #expect(records.first?.id == id)
        #expect(records.first?.lastState == .exited)
    }

    @Test("keepalive is released when process exits naturally")
    func keepaliveIsReleasedWhenProcessExitsNaturally() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let keepalive = RecordingHostdProcessKeepalive()
        let registry = HostdProcessRegistry(store: store, keepalive: keepalive)
        let id = UUID()

        _ = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .terminal,
            command: "printf done",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        try await eventually {
            let records = try await store.list()
            return keepalive.snapshot == .init(retains: 1, releases: 1, active: 0)
                && records.first?.lastState == .exited
        }
    }

    @Test("writes input and resizes the PTY")
    func writeInputAndResizePTY() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let registry = HostdProcessRegistry(store: store)
        let id = UUID()

        _ = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .terminal,
            command: "read line; stty size; printf \"input:%s\" \"$line\"; sleep 5",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        try await registry.resizeSession(id: id, columns: 100, rows: 40)
        try await registry.writeSessionInput(id: id, data: Data("hello\n".utf8))
        let text = try await readText(
            from: registry,
            id: id,
            until: { $0.contains("40 100") && $0.contains("input:hello") }
        )
        #expect(text.contains("40 100"))
        #expect(text.contains("input:hello"))

        try await registry.terminateSession(id: id)
    }

    @Test("output pump retains output before attach read")
    func outputPumpRetainsOutputBeforeAttachRead() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let registry = HostdProcessRegistry(store: store)
        let id = UUID()

        _ = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .terminal,
            command: "printf retained; sleep 5",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let output = try await waitForHostdOutput(
            from: registry,
            id: id,
            after: nil,
            contains: "retained"
        )

        #expect(String(decoding: output.chunks.flatMap(\.data), as: UTF8.self).contains("retained"))

        try await registry.terminateSession(id: id)
    }

    @Test("stream reads do not steal bytes from other clients")
    func streamReadsDoNotStealBytesFromOtherClients() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let registry = HostdProcessRegistry(store: store)
        let id = UUID()

        _ = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .terminal,
            command: "printf shared; sleep 5",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let first = try await waitForHostdOutput(
            from: registry,
            id: id,
            after: nil,
            contains: "shared"
        )
        let second = try await registry.readSessionOutputStream(id: id, after: nil, timeout: 0)

        #expect(String(decoding: first.chunks.flatMap(\.data), as: UTF8.self).contains("shared"))
        #expect(String(decoding: second.chunks.flatMap(\.data), as: UTF8.self).contains("shared"))

        try await registry.terminateSession(id: id)
    }

    @Test("sends interrupt signal to a running PTY session")
    func sendsInterruptSignalToRunningPTYSession() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let registry = HostdProcessRegistry(store: store)
        let id = UUID()

        _ = try await registry.launchSession(HostdLaunchSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .terminal,
            command: "exec perl -e '$SIG{INT}=sub{print \"interrupted\"; exit 0}; print \"ready\"; sleep 60'",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        _ = try await readText(
            from: registry,
            id: id,
            until: { $0.contains("ready") }
        )
        try await registry.sendSessionSignal(id: id, signal: .interrupt)

        let text = try await readText(
            from: registry,
            id: id,
            until: { $0.contains("interrupted") }
        )
        #expect(text.contains("interrupted"))
    }

    private func waitForHostdOutput(
        from registry: HostdProcessRegistry,
        id: UUID,
        after sequence: UInt64?,
        contains needle: String
    ) async throws -> HostdOutputRead {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let output = try await registry.readSessionOutputStream(id: id, after: sequence, timeout: 0.25)
            if String(decoding: output.chunks.flatMap(\.data), as: UTF8.self).contains(needle) {
                return output
            }
        }
        throw HostdProcessRegistryTestError.outputTimeout
    }

    private func readText(
        from registry: HostdProcessRegistry,
        id: UUID,
        until matches: (String) -> Bool
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(2)
        var text = ""
        repeat {
            let output = try await registry.readAvailableOutput(id: id, timeout: 0.25)
            text += String(decoding: output, as: UTF8.self)
        } while !matches(text) && Date() < deadline
        return text
    }

    private func eventually(_ condition: () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(try await condition())
    }
}

private enum HostdProcessRegistryTestError: Error {
    case outputTimeout
}

private final class RecordingHostdProcessKeepalive: HostdProcessKeepalive, @unchecked Sendable {
    struct Snapshot: Equatable {
        let retains: Int
        let releases: Int
        let active: Int
    }

    private let lock = NSLock()
    private var retains = 0
    private var releases = 0
    private var active = 0

    var snapshot: Snapshot {
        lock.withLock {
            Snapshot(retains: retains, releases: releases, active: active)
        }
    }

    func retainSession() {
        lock.withLock {
            retains += 1
            active += 1
        }
    }

    func releaseSession() {
        lock.withLock {
            releases += 1
            active -= 1
        }
    }
}
