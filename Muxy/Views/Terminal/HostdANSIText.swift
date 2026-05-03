import AppKit
import Foundation

struct HostdANSITextStyle: Equatable {
    var foregroundColorIndex: Int?
    var backgroundColorIndex: Int?
    var isBold: Bool
    var isDim: Bool

    init(
        foregroundColorIndex: Int? = nil,
        backgroundColorIndex: Int? = nil,
        isBold: Bool = false,
        isDim: Bool = false
    ) {
        self.foregroundColorIndex = foregroundColorIndex
        self.backgroundColorIndex = backgroundColorIndex
        self.isBold = isBold
        self.isDim = isDim
    }

    static let plain = HostdANSITextStyle()

    var isPlain: Bool {
        self == .plain
    }
}

struct HostdANSITextRun: Equatable {
    let range: NSRange
    let style: HostdANSITextStyle
}

struct HostdANSIText: Equatable {
    let plainText: String
    let runs: [HostdANSITextRun]
}

enum HostdANSITextParser {
    private struct CSISequence {
        let final: Character
        let parameters: [Int]
        let end: String.Index
    }

    static func parse(_ input: String) -> HostdANSIText {
        var index = input.startIndex
        var plainText = ""
        var runs: [HostdANSITextRun] = []
        var style = HostdANSITextStyle.plain
        var runStart: Int?
        var utf16Length = 0

        func changeStyle(to newStyle: HostdANSITextStyle) {
            if let start = runStart, start < utf16Length {
                runs.append(HostdANSITextRun(
                    range: NSRange(location: start, length: utf16Length - start),
                    style: style
                ))
            }
            style = newStyle
            runStart = newStyle.isPlain ? nil : utf16Length
        }

        func append(_ character: Character) {
            if !style.isPlain, runStart == nil {
                runStart = utf16Length
            }
            plainText.append(character)
            utf16Length += String(character).utf16.count
        }

        parseLoop: while index < input.endIndex {
            if input[index] == "\u{1B}" {
                guard let next = input.index(index, offsetBy: 1, limitedBy: input.endIndex),
                      next < input.endIndex
                else { break parseLoop }

                switch input[next] {
                case "[":
                    let sequenceStart = input.index(after: next)
                    guard let sequence = consumeCSI(in: input, from: sequenceStart) else { break parseLoop }
                    if sequence.final == "m" {
                        changeStyle(to: style.applyingSGR(sequence.parameters))
                    }
                    index = sequence.end
                    continue
                case "]":
                    let sequenceStart = input.index(after: next)
                    guard let end = consumeOSC(in: input, from: sequenceStart) else { break parseLoop }
                    index = end
                    continue
                default:
                    index = input.index(after: next)
                    continue
                }
            }

            append(input[index])
            index = input.index(after: index)
        }

        if let start = runStart, start < utf16Length {
            runs.append(HostdANSITextRun(
                range: NSRange(location: start, length: utf16Length - start),
                style: style
            ))
        }

        return HostdANSIText(plainText: plainText, runs: runs)
    }

    private static func consumeCSI(
        in input: String,
        from start: String.Index
    ) -> CSISequence? {
        var index = start
        var body = ""

        while index < input.endIndex {
            let character = input[index]
            if isCSIFinal(character) {
                let end = input.index(after: index)
                return CSISequence(final: character, parameters: sgrParameters(from: body), end: end)
            }
            body.append(character)
            index = input.index(after: index)
        }

        return nil
    }

    private static func consumeOSC(in input: String, from start: String.Index) -> String.Index? {
        var index = start

        while index < input.endIndex {
            if input[index] == "\u{07}" {
                return input.index(after: index)
            }
            if input[index] == "\u{1B}" {
                let next = input.index(after: index)
                if next < input.endIndex, input[next] == "\\" {
                    return input.index(after: next)
                }
            }
            index = input.index(after: index)
        }

        return nil
    }

    private static func isCSIFinal(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first
        else { return false }
        return scalar.value >= 0x40 && scalar.value <= 0x7E
    }

    private static func sgrParameters(from body: String) -> [Int] {
        guard !body.isEmpty else { return [0] }
        return body
            .replacingOccurrences(of: ":", with: ";")
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
    }
}

extension HostdANSITextStyle {
    func applyingSGR(_ parameters: [Int]) -> HostdANSITextStyle {
        var style = self
        var index = 0

        while index < parameters.count {
            switch parameters[index] {
            case 0:
                style = .plain
                index += 1
            case 1:
                style.isBold = true
                index += 1
            case 2:
                style.isDim = true
                index += 1
            case 22:
                style.isBold = false
                style.isDim = false
                index += 1
            case 30 ... 37:
                style.foregroundColorIndex = parameters[index] - 30
                index += 1
            case 39:
                style.foregroundColorIndex = nil
                index += 1
            case 40 ... 47:
                style.backgroundColorIndex = parameters[index] - 40
                index += 1
            case 49:
                style.backgroundColorIndex = nil
                index += 1
            case 90 ... 97:
                style.foregroundColorIndex = parameters[index] - 90 + 8
                index += 1
            case 100 ... 107:
                style.backgroundColorIndex = parameters[index] - 100 + 8
                index += 1
            case 38:
                index = applyingExtendedColor(parameters, at: index, target: \.foregroundColorIndex, to: &style)
            case 48:
                index = applyingExtendedColor(parameters, at: index, target: \.backgroundColorIndex, to: &style)
            default:
                index += 1
            }
        }

        return style
    }

    private func applyingExtendedColor(
        _ parameters: [Int],
        at index: Int,
        target: WritableKeyPath<HostdANSITextStyle, Int?>,
        to style: inout HostdANSITextStyle
    ) -> Int {
        guard index + 1 < parameters.count else { return index + 1 }

        switch parameters[index + 1] {
        case 5:
            guard index + 2 < parameters.count else { return index + 2 }
            let colorIndex = parameters[index + 2]
            if (0 ... 255).contains(colorIndex) {
                style[keyPath: target] = colorIndex
            }
            return index + 3
        case 2:
            return min(index + 5, parameters.count)
        default:
            return index + 2
        }
    }
}

@MainActor
enum HostdANSITextRenderer {
    static func attributedString(from rawText: String) -> NSAttributedString {
        let parsed = HostdANSITextParser.parse(rawText)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping

        let result = NSMutableAttributedString(
            string: parsed.plainText,
            attributes: [
                .font: font,
                .foregroundColor: GhosttyService.shared.foregroundColor,
                .paragraphStyle: paragraphStyle,
            ]
        )

        for run in parsed.runs {
            result.addAttributes(attributes(for: run.style, baseFont: font), range: run.range)
        }

        return result
    }

    private static func attributes(
        for style: HostdANSITextStyle,
        baseFont: NSFont
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        let defaultForeground = GhosttyService.shared.foregroundColor

        if style.isBold {
            attributes[.font] = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        }

        if let foregroundIndex = style.foregroundColorIndex {
            attributes[.foregroundColor] = color(at: foregroundIndex, fallback: defaultForeground, dim: style.isDim)
        } else if style.isDim {
            attributes[.foregroundColor] = defaultForeground.withAlphaComponent(0.5)
        }

        if let backgroundIndex = style.backgroundColorIndex {
            attributes[.backgroundColor] = color(at: backgroundIndex, fallback: .clear, dim: false)
        }

        return attributes
    }

    private static func color(at index: Int, fallback: NSColor, dim: Bool) -> NSColor {
        let color = GhosttyService.shared.paletteColor(at: index) ?? fallback
        guard dim else { return color }
        return color.withAlphaComponent(0.5)
    }
}
