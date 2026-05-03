import Foundation
import SwiftTerm

final class HostdTerminalSnapshotStore: @unchecked Sendable {
    private let delegate = HostdTerminalSnapshotDelegate()
    private let terminal: Terminal
    private let queue = DispatchQueue(label: "app.roost.hostd.terminalSnapshot")
    private let cacheLock = NSLock()
    private var latestSequence: UInt64 = 0
    private var cachedOutput = HostdOutputRead(chunks: [], nextSequence: 0, truncated: false)

    init(columns: UInt16, rows: UInt16) {
        terminal = Terminal(
            delegate: delegate,
            options: TerminalOptions(
                cols: Int(columns),
                rows: Int(rows),
                scrollback: 0,
                kittyImageCacheLimitBytes: 0
            )
        )
        publishSnapshot(sequence: 0)
    }

    func feed(_ data: Data, endingAt sequence: UInt64) {
        guard !data.isEmpty else { return }
        queue.async { [self] in
            applyFeed(data, endingAt: sequence)
        }
    }

    func resize(columns: UInt16, rows: UInt16) {
        queue.async { [self] in
            terminal.resize(cols: Int(columns), rows: Int(rows))
            publishSnapshot(sequence: latestSequence)
        }
    }

    func outputRead() -> HostdOutputRead {
        cacheLock.withLock { cachedOutput }
    }

    func feedImmediately(_ data: Data, endingAt sequence: UInt64) {
        guard !data.isEmpty else { return }
        queue.sync { [self] in
            applyFeed(data, endingAt: sequence)
        }
    }

    func resizeImmediately(columns: UInt16, rows: UInt16) {
        queue.sync { [self] in
            terminal.resize(cols: Int(columns), rows: Int(rows))
            publishSnapshot(sequence: latestSequence)
        }
    }

    private func applyFeed(_ data: Data, endingAt sequence: UInt64) {
        terminal.feed(byteArray: Array(data))
        latestSequence = max(latestSequence, sequence)
        publishSnapshot(sequence: latestSequence)
    }

    private func publishSnapshot(sequence: UInt64) {
        let data = HostdTerminalSnapshotSerializer(terminal: terminal).serialize()
        let output = HostdOutputRead(
            chunks: data.isEmpty ? [] : [HostdOutputChunk(sequence: sequence, data: data)],
            nextSequence: sequence,
            truncated: false
        )
        cacheLock.withLock {
            cachedOutput = output
        }
    }
}

private final class HostdTerminalSnapshotDelegate: TerminalDelegate {
    func send(source _: Terminal, data _: ArraySlice<UInt8>) {}
}

private struct HostdTerminalSnapshotSerializer {
    private let terminal: Terminal
    private let escape = "\u{1B}"

    init(terminal: Terminal) {
        self.terminal = terminal
    }

    func serialize() -> Data {
        var data = Data()
        append("\(escape)[0m", to: &data)
        append("\(escape)[?9l\(escape)[?1000l\(escape)[?1002l\(escape)[?1003l", to: &data)
        append("\(escape)[?1049l", to: &data)
        if terminal.isCurrentBufferAlternate {
            append("\(escape)[?1049h", to: &data)
        }
        append("\(escape)[2J\(escape)[H", to: &data)
        appendScreen(to: &data)
        appendModes(to: &data)
        appendCursor(to: &data)
        return data
    }

    private func appendScreen(to data: inout Data) {
        let dimensions = terminal.getDims()
        var activeAttribute: Attribute?
        for row in 0 ..< dimensions.rows {
            guard let line = terminal.getLine(row: row),
                  let lastColumn = lastContentColumn(in: line, columns: dimensions.cols)
            else { continue }

            append("\(escape)[\(row + 1);1H", to: &data)
            for column in 0 ... lastColumn {
                let cell = line[column]
                if cell.width == 0 { continue }
                if activeAttribute != cell.attribute {
                    append("\(escape)[\(sgr(cell.attribute))", to: &data)
                    activeAttribute = cell.attribute
                }
                append(character(for: cell), to: &data)
            }
        }
        append("\(escape)[0m", to: &data)
    }

    private func appendModes(to data: inout Data) {
        if terminal.applicationCursor {
            append("\(escape)[?1h", to: &data)
        }
        if terminal.bracketedPasteMode {
            append("\(escape)[?2004h", to: &data)
        }
        switch terminal.mouseMode {
        case .off:
            break
        case .x10:
            append("\(escape)[?9h", to: &data)
        case .vt200:
            append("\(escape)[?1000h", to: &data)
        case .buttonEventTracking:
            append("\(escape)[?1002h", to: &data)
        case .anyEvent:
            append("\(escape)[?1003h", to: &data)
        }
    }

    private func appendCursor(to data: inout Data) {
        let dimensions = terminal.getDims()
        let column = min(max(terminal.buffer.x, 0), max(dimensions.cols - 1, 0)) + 1
        let row = min(max(terminal.buffer.y, 0), max(dimensions.rows - 1, 0)) + 1
        append("\(escape)[\(row);\(column)H", to: &data)
    }

    private func lastContentColumn(in line: BufferLine, columns: Int) -> Int? {
        var result: Int?
        let limit = min(line.count, columns)
        guard limit > 0 else { return nil }
        for column in 0 ..< limit where line.hasContent(index: column) {
            result = column
        }
        return result
    }

    private func character(for cell: CharData) -> String {
        let character = terminal.getCharacter(for: cell)
        if character == "\u{0}" { return " " }
        return String(character)
    }

    private func sgr(_ attribute: Attribute) -> String {
        var values = ["0"]
        if attribute.style.contains(.bold) { values.append("1") }
        if attribute.style.contains(.dim) { values.append("2") }
        if attribute.style.contains(.italic) { values.append("3") }
        if attribute.style.contains(.underline) { values.append("4") }
        if attribute.style.contains(.blink) { values.append("5") }
        if attribute.style.contains(.inverse) { values.append("7") }
        if attribute.style.contains(.invisible) { values.append("8") }
        if attribute.style.contains(.crossedOut) { values.append("9") }
        values.append(contentsOf: sgrColor(attribute.fg, foreground: true))
        values.append(contentsOf: sgrColor(attribute.bg, foreground: false))
        return "\(values.joined(separator: ";"))m"
    }

    private func sgrColor(_ color: Attribute.Color, foreground: Bool) -> [String] {
        switch color {
        case let .ansi256(code):
            if code < 8 {
                return ["\((foreground ? 30 : 40) + Int(code))"]
            }
            if code < 16 {
                return ["\((foreground ? 90 : 100) + Int(code - 8))"]
            }
            return [foreground ? "38" : "48", "5", "\(code)"]
        case let .trueColor(red, green, blue):
            return [foreground ? "38" : "48", "2", "\(red)", "\(green)", "\(blue)"]
        case .defaultColor,
             .defaultInvertedColor:
            return []
        }
    }

    private func append(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }
}
