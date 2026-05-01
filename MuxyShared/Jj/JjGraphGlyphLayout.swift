import Foundation

public struct JjGraphGlyphLayout: Hashable, Sendable {
    public let lines: [JjGraphGlyphLine]
    public let columnCount: Int

    public init(lines: [String]) {
        self.lines = lines.map(JjGraphGlyphLine.init(rawText:))
        columnCount = self.lines.map(\.columnCount).max() ?? 0
    }

    public init(entry: JjLogEntry) {
        self.init(lines: entry.graphDisplayLines)
    }

    public static func cellCount(for line: String) -> Int {
        let count = line.graphTrailingWhitespaceTrimmedCount
        guard count > 0 else { return 0 }
        return Int(ceil(Double(count) / 2.0))
    }
}

public struct JjGraphGlyphLine: Hashable, Sendable {
    public let rawText: String
    public let cells: [JjGraphGlyphCell]

    public var columnCount: Int {
        cells.count
    }

    public init(rawText: String) {
        self.rawText = rawText
        let characters = Array(rawText)
        let cellCount = JjGraphGlyphLayout.cellCount(for: rawText)
        cells = (0 ..< cellCount).map { column in
            let start = column * 2
            let first = start < characters.count ? String(characters[start]) : " "
            let second = start + 1 < characters.count ? String(characters[start + 1]) : " "
            let rawGlyph = first + second
            return JjGraphGlyphCell(column: column, rawText: rawGlyph, glyph: JjGraphGlyph(rawText: rawGlyph))
        }
    }
}

public struct JjGraphGlyphCell: Hashable, Sendable {
    public let column: Int
    public let rawText: String
    public let glyph: JjGraphGlyph

    public init(column: Int, rawText: String, glyph: JjGraphGlyph) {
        self.column = column
        self.rawText = rawText
        self.glyph = glyph
    }
}

public enum JjGraphGlyph: Hashable, Sendable {
    case empty
    case horizontal
    case vertical
    case ancestor
    case bendLeftUp
    case bendRightUp
    case horizontalUp
    case bendLeftDown
    case bendRightDown
    case horizontalDown
    case verticalLeft
    case verticalRight
    case cross
    case elided
    case node(String)
    case unknown(String)

    public init(rawText: String) {
        switch rawText {
        case "  ": self = .empty
        case "──": self = .horizontal
        case "│ ": self = .vertical
        case "╷ ": self = .ancestor
        case "╯ ": self = .bendLeftUp
        case "╰─": self = .bendRightUp
        case "┴─": self = .horizontalUp
        case "╮ ": self = .bendLeftDown
        case "╭─": self = .bendRightDown
        case "┬─": self = .horizontalDown
        case "┤ ": self = .verticalLeft
        case "├─": self = .verticalRight
        case "┼─": self = .cross
        case "~ ": self = .elided
        default:
            if let node = rawText.firstGraphNodeCharacter {
                self = .node(String(node))
            } else if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self = .empty
            } else {
                self = .unknown(rawText)
            }
        }
    }

    public var edges: JjGraphGlyphEdges {
        switch self {
        case .horizontal:
            [.left, .right]
        case .vertical:
            [.top, .bottom]
        case .ancestor:
            [.bottom]
        case .bendLeftUp:
            [.top, .left]
        case .bendRightUp:
            [.top, .right]
        case .horizontalUp:
            [.left, .right, .top]
        case .bendLeftDown:
            [.left, .bottom]
        case .bendRightDown:
            [.right, .bottom]
        case .horizontalDown:
            [.left, .right, .bottom]
        case .verticalLeft:
            [.top, .bottom, .left]
        case .verticalRight:
            [.top, .bottom, .right]
        case .cross:
            [.top, .bottom, .left, .right]
        case .empty,
             .elided,
             .node,
             .unknown:
            []
        }
    }
}

public struct JjGraphGlyphEdges: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let top = JjGraphGlyphEdges(rawValue: 1 << 0)
    public static let bottom = JjGraphGlyphEdges(rawValue: 1 << 1)
    public static let left = JjGraphGlyphEdges(rawValue: 1 << 2)
    public static let right = JjGraphGlyphEdges(rawValue: 1 << 3)
}

public extension JjLogEntry {
    var graphDisplayColumnCount: Int {
        graphDisplayLines.map(JjGraphGlyphLayout.cellCount(for:)).max() ?? 0
    }
}

private extension String {
    var graphTrailingWhitespaceTrimmedCount: Int {
        var trimmedEnd = endIndex
        while trimmedEnd > startIndex {
            let previous = index(before: trimmedEnd)
            guard self[previous].isWhitespace else { break }
            trimmedEnd = previous
        }
        return distance(from: startIndex, to: trimmedEnd)
    }

    var firstGraphNodeCharacter: Character? {
        first { character in
            !character.isWhitespace && !jjGraphConnectorCharacters.contains(character)
        }
    }
}

private let jjGraphConnectorCharacters: Set<Character> = [
    "─", "│", "╷", "╯", "╰", "┴", "╮", "╭", "┬", "┤", "├", "┼", "~",
]
