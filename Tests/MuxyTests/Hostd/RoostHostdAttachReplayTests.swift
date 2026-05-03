import Foundation
import RoostHostdCore
import Testing
@testable import RoostHostdAttach

@Suite("RoostHostdAttach replay", .serialized)
struct RoostHostdAttachReplayTests {
    @Test("initial replay reads retained output without byte limit")
    func initialReplayReadsRetainedOutputWithoutByteLimit() async throws {
        let sessionID = UUID()
        let client = RecordingAttachOutputReader()
        var replay = HostdAttachOutputReplay(sessionID: sessionID, client: client)

        _ = try await replay.readNext()

        #expect(await client.requests == [
            RecordingAttachOutputRequest(id: sessionID, after: nil, timeout: 0.25, limit: nil),
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
            RecordingAttachOutputRequest(id: sessionID, after: nil, timeout: 0.25, limit: nil),
            RecordingAttachOutputRequest(id: sessionID, after: 42, timeout: 0.25, limit: nil),
        ])
    }
}

private struct RecordingAttachOutputRequest: Equatable {
    let id: UUID
    let after: UInt64?
    let timeout: TimeInterval
    let limit: Int?
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
        limit: Int?
    ) async throws -> HostdOutputRead {
        requests.append(RecordingAttachOutputRequest(
            id: id,
            after: sequence,
            timeout: timeout,
            limit: limit
        ))
        if outputs.isEmpty {
            return HostdOutputRead(chunks: [], nextSequence: sequence ?? 0, truncated: false)
        }
        return outputs.removeFirst()
    }
}
