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

        try await registry.terminateSession(id: id)
        let records = try await store.list()
        #expect(records.first?.id == id)
        #expect(records.first?.lastState == .exited)
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
}
