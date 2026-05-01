import Foundation

struct JjConflictMarkerPreview: Equatable, Sendable {
    let regions: [JjConflictMarkerRegion]
    fileprivate let segments: [JjConflictMarkerSegment]

    func resolvedText(replacements: [Int: String]) -> String {
        var lines: [String] = []
        for segment in segments {
            switch segment {
            case let .text(textLines):
                lines.append(contentsOf: textLines)
            case let .conflict(region):
                let replacement = replacements[region.index] ?? region.current
                lines.append(contentsOf: replacement.components(separatedBy: .newlines))
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct JjConflictMarkerRegion: Equatable, Identifiable, Sendable {
    let index: Int
    let base: String
    let current: String
    let incoming: String

    var id: Int { index }
}

private enum JjConflictMarkerSegment: Equatable, Sendable {
    case text([String])
    case conflict(JjConflictMarkerRegion)
}

enum JjConflictMarkerParser {
    static func parse(_ text: String) -> JjConflictMarkerPreview {
        let lines = text.components(separatedBy: .newlines)
        var regions: [JjConflictMarkerRegion] = []
        var segments: [JjConflictMarkerSegment] = []
        var textLines: [String] = []
        var index = 0

        while index < lines.count {
            guard lines[index].hasPrefix("<<<<<<<") else {
                textLines.append(lines[index])
                index += 1
                continue
            }

            let markerStart = lines[index]
            index += 1
            var body: [String] = []
            while index < lines.count, !lines[index].hasPrefix(">>>>>>>") {
                body.append(lines[index])
                index += 1
            }
            let markerEnd = index < lines.count ? lines[index] : nil
            if index < lines.count {
                index += 1
            }

            if let region = parseBody(body, index: regions.count + 1) {
                appendTextSegment(&segments, lines: &textLines)
                regions.append(region)
                segments.append(.conflict(region))
            } else {
                textLines.append(markerStart)
                textLines.append(contentsOf: body)
                if let markerEnd {
                    textLines.append(markerEnd)
                }
            }
        }

        appendTextSegment(&segments, lines: &textLines)
        return JjConflictMarkerPreview(regions: regions, segments: segments)
    }

    private static func appendTextSegment(_ segments: inout [JjConflictMarkerSegment], lines: inout [String]) {
        guard !lines.isEmpty else { return }
        segments.append(.text(lines))
        lines.removeAll()
    }

    private static func parseBody(_ lines: [String], index: Int) -> JjConflictMarkerRegion? {
        if lines.contains(where: { $0.hasPrefix("%%%%%%%") || $0.hasPrefix("+++++++") }) {
            return parseJjBody(lines, index: index)
        }
        return parseGitBody(lines, index: index)
    }

    private static func parseJjBody(_ lines: [String], index: Int) -> JjConflictMarkerRegion? {
        enum Mode {
            case waiting
            case diff
            case current
            case incoming
        }

        var mode = Mode.waiting
        var base: [String] = []
        var current: [String] = []
        var incoming: [String] = []

        for line in lines {
            if line.hasPrefix("%%%%%%%") {
                mode = .diff
                continue
            }
            if line.hasPrefix("\\\\\\\\\\\\\\") {
                continue
            }
            if line.hasPrefix("-------") {
                mode = .current
                continue
            }
            if line.hasPrefix("+++++++") {
                mode = .incoming
                continue
            }

            switch mode {
            case .waiting:
                continue
            case .diff:
                appendDiffLine(line, base: &base, current: &current)
            case .current:
                current.append(line)
            case .incoming:
                incoming.append(line)
            }
        }

        guard !base.isEmpty || !current.isEmpty || !incoming.isEmpty else { return nil }
        return JjConflictMarkerRegion(
            index: index,
            base: joined(base),
            current: joined(current),
            incoming: joined(incoming)
        )
    }

    private static func parseGitBody(_ lines: [String], index: Int) -> JjConflictMarkerRegion? {
        enum Mode {
            case current
            case base
            case incoming
        }

        var mode = Mode.current
        var sawSeparator = false
        var base: [String] = []
        var current: [String] = []
        var incoming: [String] = []

        for line in lines {
            if line.hasPrefix("|||||||") {
                mode = .base
                continue
            }
            if line.hasPrefix("=======") {
                mode = .incoming
                sawSeparator = true
                continue
            }

            switch mode {
            case .current:
                current.append(line)
            case .base:
                base.append(line)
            case .incoming:
                incoming.append(line)
            }
        }

        guard sawSeparator else { return nil }
        return JjConflictMarkerRegion(
            index: index,
            base: joined(base),
            current: joined(current),
            incoming: joined(incoming)
        )
    }

    private static func appendDiffLine(_ line: String, base: inout [String], current: inout [String]) {
        if line.hasPrefix("-") {
            base.append(String(line.dropFirst()))
        } else if line.hasPrefix("+") {
            current.append(String(line.dropFirst()))
        } else if line.hasPrefix(" ") {
            let value = String(line.dropFirst())
            base.append(value)
            current.append(value)
        } else {
            base.append(line)
            current.append(line)
        }
    }

    private static func joined(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }
}
