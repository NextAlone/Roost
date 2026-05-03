import Foundation
import MuxyShared
import RoostHostdCore
import Testing

@testable import Roost

@Suite("HostdOwnedTerminalOutputModel")
@MainActor
struct HostdOwnedTerminalOutputModelTests {
    @Test("stream appends hostd output chunks")
    func streamAppendsOutputChunks() async throws {
        let client = FakeHostdOutputClient(outputs: [
            Data("hello ".utf8),
            Data("world".utf8),
        ])
        let model = HostdOwnedTerminalOutputModel(bufferLimit: 1024)
        let paneID = UUID()

        let task = Task {
            await model.stream(
                client: client,
                paneID: paneID,
                timeout: 0,
                idleSleepNanoseconds: 1_000_000,
                errorSleepNanoseconds: 1_000_000
            )
        }
        try await client.waitForReadCount(2)
        task.cancel()
        await task.value

        #expect(model.text == "hello world")
        #expect(model.status == .streaming)
    }

    @Test("stream attaches before reading and releases after cancellation")
    func streamAttachesBeforeReadingAndReleasesAfterCancellation() async throws {
        let client = FakeHostdOutputClient(outputs: [
            Data("attached".utf8),
        ])
        let model = HostdOwnedTerminalOutputModel(bufferLimit: 1024)
        let paneID = UUID()

        let task = Task {
            await model.stream(
                client: client,
                paneID: paneID,
                timeout: 0,
                idleSleepNanoseconds: 1_000_000,
                errorSleepNanoseconds: 1_000_000
            )
        }
        try await client.waitForReadCount(1)
        task.cancel()
        await task.value

        #expect(await client.attachRequests() == [paneID])
        #expect(await client.releaseRequests() == [paneID])
    }

    @Test("stream caps output buffer")
    func streamCapsOutputBuffer() async throws {
        let client = FakeHostdOutputClient(outputs: [
            Data("abcdef".utf8),
            Data("ghijkl".utf8),
        ])
        let model = HostdOwnedTerminalOutputModel(bufferLimit: 8)

        let task = Task {
            await model.stream(
                client: client,
                paneID: UUID(),
                timeout: 0,
                idleSleepNanoseconds: 1_000_000,
                errorSleepNanoseconds: 1_000_000
            )
        }
        try await client.waitForReadCount(2)
        task.cancel()
        await task.value

        #expect(model.text == "efghijkl")
    }

    @Test("sendInput writes hostd input data")
    func sendInputWritesHostdInputData() async throws {
        let client = FakeHostdOutputClient(outputs: [])
        let model = HostdOwnedTerminalOutputModel(bufferLimit: 1024)
        let paneID = UUID()
        let input = Data("ping\r".utf8)

        await model.sendInput(client: client, paneID: paneID, data: input)

        #expect(await client.writtenInputs() == [input])
    }

    @Test("sendInput reports missing client")
    func sendInputReportsMissingClient() async throws {
        let model = HostdOwnedTerminalOutputModel(bufferLimit: 1024)

        await model.sendInput(client: nil, paneID: UUID(), data: Data("x".utf8))

        #expect(model.status == .failed("Hostd client unavailable"))
    }

    @Test("sendSignal forwards hostd interrupt signal")
    func sendSignalForwardsHostdInterruptSignal() async throws {
        let client = FakeHostdOutputClient(outputs: [])
        let model = HostdOwnedTerminalOutputModel(bufferLimit: 1024)
        let paneID = UUID()

        await model.sendSignal(client: client, paneID: paneID, signal: .interrupt)

        #expect(await client.signals() == [
            HostdSignalRequest(id: paneID, signal: .interrupt),
        ])
    }

    @Test("resize writes hostd grid once per size")
    func resizeWritesHostdGridOncePerSize() async throws {
        let client = FakeHostdOutputClient(outputs: [])
        let model = HostdOwnedTerminalOutputModel(bufferLimit: 1024)
        let paneID = UUID()
        let size = CGSize(width: 160, height: 80)

        await model.resize(
            client: client,
            paneID: paneID,
            size: size,
            cellSize: CGSize(width: 8, height: 16),
            horizontalPadding: 0,
            verticalPadding: 0
        )
        await model.resize(
            client: client,
            paneID: paneID,
            size: size,
            cellSize: CGSize(width: 8, height: 16),
            horizontalPadding: 0,
            verticalPadding: 0
        )

        #expect(await client.resizeRequests() == [
            HostdResizeRequest(id: paneID, columns: 20, rows: 5),
        ])
    }

    @Test("resize reports missing client")
    func resizeReportsMissingClient() async throws {
        let model = HostdOwnedTerminalOutputModel(bufferLimit: 1024)

        await model.resize(client: nil, paneID: UUID(), size: CGSize(width: 160, height: 80))

        #expect(model.status == .failed("Hostd client unavailable"))
    }
}

private actor FakeHostdOutputClient: RoostHostdClient {
    let runtimeOwnershipHint: HostdRuntimeOwnership? = .hostdOwnedProcess
    private var outputs: [Data]
    private var readCount = 0
    private var attachRecords: [UUID] = []
    private var releaseRecords: [UUID] = []
    private var inputs: [Data] = []
    private var resizeRecords: [HostdResizeRequest] = []
    private var signalRecords: [HostdSignalRequest] = []

    init(outputs: [Data]) {
        self.outputs = outputs
    }

    func runtimeOwnership() async throws -> HostdRuntimeOwnership {
        .hostdOwnedProcess
    }

    func createSession(_ request: HostdCreateSessionRequest) async throws {}

    func attachSession(id: UUID) async throws -> HostdAttachSessionResponse {
        attachRecords.append(id)
        return HostdAttachSessionResponse(
            record: SessionRecord(
                id: id,
                projectID: UUID(),
                worktreeID: UUID(),
                workspacePath: "/tmp",
                agentKind: .terminal,
                command: nil,
                createdAt: Date(timeIntervalSince1970: 0),
                lastState: .running
            ),
            ownership: .hostdOwnedProcess
        )
    }

    func releaseSession(id: UUID) async throws {
        releaseRecords.append(id)
    }

    func terminateSession(id: UUID) async throws {}

    func readSessionOutput(id: UUID, timeout: TimeInterval) async throws -> Data {
        readCount += 1
        guard !outputs.isEmpty else { return Data() }
        return outputs.removeFirst()
    }

    func writeSessionInput(id: UUID, data: Data) async throws {
        inputs.append(data)
    }

    func resizeSession(id: UUID, columns: UInt16, rows: UInt16) async throws {
        resizeRecords.append(HostdResizeRequest(id: id, columns: columns, rows: rows))
    }

    func sendSessionSignal(id: UUID, signal: HostdSessionSignal) async throws {
        signalRecords.append(HostdSignalRequest(id: id, signal: signal))
    }

    func markExited(sessionID: UUID) async throws {}

    func listLiveSessions() async throws -> [SessionRecord] { [] }

    func listAllSessions() async throws -> [SessionRecord] { [] }

    func deleteSession(id: UUID) async throws {}

    func pruneExited() async throws {}

    func markAllRunningExited() async throws {}

    func waitForReadCount(_ target: Int) async throws {
        for _ in 0 ..< 100 {
            if readCount >= target { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        Issue.record("Expected \(target) output reads, got \(readCount)")
    }

    func attachRequests() -> [UUID] {
        attachRecords
    }

    func releaseRequests() -> [UUID] {
        releaseRecords
    }

    func writtenInputs() -> [Data] {
        inputs
    }

    func resizeRequests() -> [HostdResizeRequest] {
        resizeRecords
    }

    func signals() -> [HostdSignalRequest] {
        signalRecords
    }
}

private struct HostdResizeRequest: Equatable {
    let id: UUID
    let columns: UInt16
    let rows: UInt16
}

private struct HostdSignalRequest: Equatable {
    let id: UUID
    let signal: HostdSessionSignal
}
