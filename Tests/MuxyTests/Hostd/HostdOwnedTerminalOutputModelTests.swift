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
}

private actor FakeHostdOutputClient: RoostHostdClient {
    let runtimeOwnershipHint: HostdRuntimeOwnership? = .hostdOwnedProcess
    private var outputs: [Data]
    private var readCount = 0
    private var inputs: [Data] = []

    init(outputs: [Data]) {
        self.outputs = outputs
    }

    func runtimeOwnership() async throws -> HostdRuntimeOwnership {
        .hostdOwnedProcess
    }

    func createSession(_ request: HostdCreateSessionRequest) async throws {}

    func readSessionOutput(id: UUID, timeout: TimeInterval) async throws -> Data {
        readCount += 1
        guard !outputs.isEmpty else { return Data() }
        return outputs.removeFirst()
    }

    func writeSessionInput(id: UUID, data: Data) async throws {
        inputs.append(data)
    }

    func resizeSession(id: UUID, columns: UInt16, rows: UInt16) async throws {}

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

    func writtenInputs() -> [Data] {
        inputs
    }
}
