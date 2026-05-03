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
}
