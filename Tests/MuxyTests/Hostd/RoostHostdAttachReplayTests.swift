import Foundation
import RoostHostdCore
import Testing
@testable import RoostHostdAttach

@Suite("RoostHostdAttach replay", .serialized)
struct RoostHostdAttachReplayTests {
    @Test("initial replay reads terminal snapshot without byte limit")
    func initialReplayReadsTerminalSnapshotWithoutByteLimit() async throws {
        let sessionID = UUID()
        let client = RecordingAttachOutputReader()
        var replay = HostdAttachOutputReplay(sessionID: sessionID, client: client)

        _ = try await replay.readNext()

        #expect(await client.requests == [
            RecordingAttachOutputRequest(id: sessionID, after: nil, timeout: 0.25, limit: nil, mode: .terminalSnapshot),
        ])
    }

    @Test("later replay resumes by sequence without byte limit")
    func laterReplayResumesBySequenceWithoutByteLimit() async throws {
        let sessionID = UUID()
        let client = RecordingAttachOutputReader(outputs: [
            HostdOutputRead(chunks: [], nextSequence: 42, truncated: false),
            HostdOutputRead(chunks: [], nextSequence: 84, truncated: false),
        ])
        var replay = HostdAttachOutputReplay(sessionID: sessionID, client: client)

        _ = try await replay.readNext()
        _ = try await replay.readNext()

        #expect(await client.requests == [
            RecordingAttachOutputRequest(id: sessionID, after: nil, timeout: 0.25, limit: nil, mode: .terminalSnapshot),
            RecordingAttachOutputRequest(id: sessionID, after: 42, timeout: 0.25, limit: nil, mode: .raw),
        ])
    }
}

private struct RecordingAttachOutputRequest: Equatable {
    let id: UUID
    let after: UInt64?
    let timeout: TimeInterval
    let limit: Int?
    let mode: HostdOutputStreamReadMode
}

private actor RecordingAttachOutputReader: HostdAttachOutputReading {
    private(set) var requests: [RecordingAttachOutputRequest] = []
    private var outputs: [HostdOutputRead]

    init(outputs: [HostdOutputRead] = [
        HostdOutputRead(chunks: [], nextSequence: 0, truncated: false),
    ]) {
        self.outputs = outputs
    }

    func readSessionOutputStream(
        id: UUID,
        after sequence: UInt64?,
        timeout: TimeInterval,
        limit: Int?,
        mode: HostdOutputStreamReadMode
    ) async throws -> HostdOutputRead {
        requests.append(RecordingAttachOutputRequest(
            id: id,
            after: sequence,
            timeout: timeout,
            limit: limit,
            mode: mode
        ))
        if outputs.isEmpty {
            return HostdOutputRead(chunks: [], nextSequence: sequence ?? 0, truncated: false)
        }
        return outputs.removeFirst()
    }
}
