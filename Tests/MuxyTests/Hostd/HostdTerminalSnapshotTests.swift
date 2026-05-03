import Foundation
import RoostHostdCore
import Testing

@testable import RoostHostdCore

@Suite("Hostd terminal snapshot", .serialized)
struct HostdTerminalSnapshotTests {
    @Test("snapshot serializes cell attributes instead of raw history")
    func snapshotSerializesCellAttributes() {
        let snapshot = HostdTerminalSnapshotStore(columns: 40, rows: 6)
        snapshot.feedImmediately(Data("\u{1B}[31m-red\u{1B}[0m\r\n\u{1B}[32m+green\u{1B}[0m".utf8), endingAt: 128)

        let output = snapshot.outputRead()
        let text = String(decoding: output.chunks.flatMap(\.data), as: UTF8.self)

        #expect(output.nextSequence == 128)
        #expect(text.contains("\u{1B}[0;31m-red"))
        #expect(text.contains("\u{1B}[0;32m+green"))
        #expect(text.contains("\u{1B}[2J\u{1B}[H"))
    }

    @Test("snapshot size is bounded by terminal dimensions")
    func snapshotSizeIsBoundedByTerminalDimensions() {
        let snapshot = HostdTerminalSnapshotStore(columns: 80, rows: 24)
        let data = Data(String(repeating: "\u{1B}[35m0123456789abcdefghijklmnopqrstuvwxyz\r\n", count: 12_000).utf8)
        snapshot.feedImmediately(data, endingAt: UInt64(data.count))

        let output = snapshot.outputRead()
        let count = output.chunks.reduce(0) { $0 + $1.data.count }

        #expect(count < 32 * 1024)
        #expect(output.nextSequence == UInt64(data.count))
    }

    @Test("alternate buffer snapshot restores alternate screen before content")
    func alternateBufferSnapshotRestoresAlternateScreen() {
        let snapshot = HostdTerminalSnapshotStore(columns: 20, rows: 4)
        snapshot.feedImmediately(Data("\u{1B}[?1049h\u{1B}[H\u{1B}[3malt".utf8), endingAt: 7)

        let output = snapshot.outputRead()
        let text = String(decoding: output.chunks.flatMap(\.data), as: UTF8.self)

        #expect(text.contains("\u{1B}[?1049h"))
        #expect(text.contains("\u{1B}[0;3malt"))
        #expect(output.nextSequence == 7)
    }

    @Test("async feed does not block cached snapshot reads")
    func asyncFeedDoesNotBlockCachedSnapshotReads() {
        let snapshot = HostdTerminalSnapshotStore(columns: 80, rows: 24)
        snapshot.feedImmediately(Data("ready".utf8), endingAt: 5)

        let largeUpdate = Data(String(repeating: "\u{1B}[31m0123456789abcdefghijklmnopqrstuvwxyz\r\n", count: 20_000).utf8)
        snapshot.feed(largeUpdate, endingAt: UInt64(largeUpdate.count) + 5)

        let output = snapshot.outputRead()
        let text = String(decoding: output.chunks.flatMap(\.data), as: UTF8.self)

        #expect(output.nextSequence >= 5)
        #expect(text.contains("ready"))
    }
}
