import Foundation
import RoostHostdCore
import Testing

@Suite("HostdOutputRingBuffer", .serialized)
struct HostdOutputRingBufferTests {
    @Test("append assigns monotonic sequences")
    func appendAssignsMonotonicSequences() {
        var buffer = HostdOutputRingBuffer(limit: 16)

        buffer.append(Data("abc".utf8))
        buffer.append(Data("def".utf8))

        #expect(buffer.read(after: nil) == HostdOutputRead(
            chunks: [HostdOutputChunk(sequence: 0, data: Data("abcdef".utf8))],
            nextSequence: 6,
            truncated: false
        ))
    }

    @Test("read from sequence returns suffix")
    func readFromSequenceReturnsSuffix() {
        var buffer = HostdOutputRingBuffer(limit: 16)
        buffer.append(Data("abcdef".utf8))

        #expect(buffer.read(after: 3) == HostdOutputRead(
            chunks: [HostdOutputChunk(sequence: 3, data: Data("def".utf8))],
            nextSequence: 6,
            truncated: false
        ))
    }

    @Test("stale sequence resumes at retained boundary")
    func staleSequenceResumesAtRetainedBoundary() {
        var buffer = HostdOutputRingBuffer(limit: 4)
        buffer.append(Data("abcdef".utf8))

        #expect(buffer.read(after: 0) == HostdOutputRead(
            chunks: [HostdOutputChunk(sequence: 2, data: Data("cdef".utf8))],
            nextSequence: 6,
            truncated: true
        ))
    }

    @Test("repeated reads do not consume retained bytes")
    func repeatedReadsDoNotConsumeRetainedBytes() {
        var buffer = HostdOutputRingBuffer(limit: 16)
        buffer.append(Data("shared".utf8))

        let first = buffer.read(after: nil)
        let second = buffer.read(after: nil)

        #expect(first == second)
    }
}
