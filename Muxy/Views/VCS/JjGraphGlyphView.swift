import MuxyShared
import SwiftUI

enum JjGraphMetrics {
    static let columnWidth: CGFloat = 14
    static let lineHeight: CGFloat = 20
    static let rowHeight: CGFloat = 40
    static let leftInset: CGFloat = 6
    static let rightInset: CGFloat = 10
    static let nodeRadius: CGFloat = 3.5
    static let strokeWidth: CGFloat = 1.1
    static let cornerRadius: CGFloat = 6

    static func width(columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return leftInset + rightInset }
        return leftInset + rightInset + CGFloat(columnCount - 1) * columnWidth + nodeRadius * 2
    }
}

struct JjGraphGlyphBlock: View {
    let layout: JjGraphGlyphLayout
    let graphColumnWidth: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        let lineColor = MuxyTheme.fgDim.opacity(0.82)
        let lineSoftColor = MuxyTheme.fgDim.opacity(0.72)
        let accentColor = MuxyTheme.accent

        Canvas { context, size in
            var renderer = JjGraphGlyphRenderer(
                context: &context,
                size: size,
                layout: layout,
                lineColor: lineColor,
                lineSoftColor: lineSoftColor,
                accentColor: accentColor
            )
            renderer.draw()
        }
        .frame(width: graphColumnWidth, height: rowHeight, alignment: .topLeading)
    }
}

private struct JjGraphGlyphRenderer {
    var context: GraphicsContext
    let size: CGSize
    let layout: JjGraphGlyphLayout
    let lineColor: Color
    let lineSoftColor: Color
    let accentColor: Color

    init(
        context: inout GraphicsContext,
        size: CGSize,
        layout: JjGraphGlyphLayout,
        lineColor: Color,
        lineSoftColor: Color,
        accentColor: Color
    ) {
        self.context = context
        self.size = size
        self.layout = layout
        self.lineColor = lineColor
        self.lineSoftColor = lineSoftColor
        self.accentColor = accentColor
    }

    mutating func draw() {
        let style = StrokeStyle(lineWidth: JjGraphMetrics.strokeWidth, lineCap: .round, lineJoin: .round)
        for lineIndex in layout.lines.indices {
            for cell in layout.lines[lineIndex].cells {
                drawConnector(cell.glyph, lineIndex: lineIndex, column: cell.column, style: style)
            }
        }
        for lineIndex in layout.lines.indices {
            for cell in layout.lines[lineIndex].cells {
                drawNode(cell.glyph, lineIndex: lineIndex, column: cell.column, style: style)
            }
        }
    }

    private mutating func drawConnector(_ glyph: JjGraphGlyph, lineIndex: Int, column: Int, style: StrokeStyle) {
        switch glyph {
        case .empty,
             .node,
             .unknown:
            return
        case .horizontal:
            drawHorizontal(lineIndex: lineIndex, column: column, left: true, right: true, style: style)
        case .vertical:
            drawVertical(lineIndex: lineIndex, column: column, up: true, down: true, style: style)
        case .ancestor:
            drawVertical(lineIndex: lineIndex, column: column, up: false, down: true, style: style)
        case .bendLeftUp:
            drawCurve(lineIndex: lineIndex, column: column, from: .top, to: .left, style: style)
        case .bendRightUp:
            drawCurve(lineIndex: lineIndex, column: column, from: .top, to: .right, style: style)
        case .horizontalUp:
            drawHorizontal(lineIndex: lineIndex, column: column, left: true, right: true, style: style)
            drawVertical(lineIndex: lineIndex, column: column, up: true, down: false, style: style)
        case .bendLeftDown:
            drawCurve(lineIndex: lineIndex, column: column, from: .left, to: .bottom, style: style)
        case .bendRightDown:
            drawCurve(lineIndex: lineIndex, column: column, from: .bottom, to: .right, style: style)
        case .horizontalDown:
            drawHorizontal(lineIndex: lineIndex, column: column, left: true, right: true, style: style)
            drawVertical(lineIndex: lineIndex, column: column, up: false, down: true, style: style)
        case .verticalLeft:
            drawVertical(lineIndex: lineIndex, column: column, up: true, down: true, style: style)
            drawHorizontal(lineIndex: lineIndex, column: column, left: true, right: false, style: style)
        case .verticalRight:
            drawVertical(lineIndex: lineIndex, column: column, up: true, down: true, style: style)
            drawHorizontal(lineIndex: lineIndex, column: column, left: false, right: true, style: style)
        case .cross:
            drawVertical(lineIndex: lineIndex, column: column, up: true, down: true, style: style)
            drawHorizontal(lineIndex: lineIndex, column: column, left: true, right: true, style: style)
        case .elided:
            drawElided(lineIndex: lineIndex, column: column, style: style)
        }
    }

    private mutating func drawNode(_ glyph: JjGraphGlyph, lineIndex: Int, column: Int, style: StrokeStyle) {
        guard case let .node(label) = glyph else { return }
        let center = point(lineIndex: lineIndex, column: column)
        let radius = JjGraphMetrics.nodeRadius
        if connectsAbove(lineIndex: lineIndex, column: column) {
            var path = Path()
            path.move(to: CGPoint(x: center.x, y: topY(lineIndex: lineIndex)))
            path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
            context.stroke(path, with: .color(lineColor), style: style)
        }
        if connectsBelow(lineIndex: lineIndex, column: column) {
            var path = Path()
            path.move(to: CGPoint(x: center.x, y: center.y + radius))
            path.addLine(to: CGPoint(x: center.x, y: bottomY(lineIndex: lineIndex)))
            context.stroke(path, with: .color(lineColor), style: style)
        }

        switch label {
        case "@":
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(accentColor.opacity(0.16)))
            context.stroke(Path(ellipseIn: rect), with: .color(accentColor), style: style)
        case "◆":
            var path = Path()
            path.move(to: CGPoint(x: center.x, y: center.y - radius))
            path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
            path.closeSubpath()
            context.fill(path, with: .color(lineSoftColor))
        default:
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(lineColor), style: style)
        }
    }

    private enum Edge {
        case top
        case bottom
        case left
        case right
    }

    private mutating func drawVertical(lineIndex: Int, column: Int, up: Bool, down: Bool, style: StrokeStyle) {
        let center = point(lineIndex: lineIndex, column: column)
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: up ? topY(lineIndex: lineIndex) : center.y))
        path.addLine(to: CGPoint(x: center.x, y: down ? bottomY(lineIndex: lineIndex) : center.y))
        context.stroke(path, with: .color(lineColor), style: style)
    }

    private mutating func drawHorizontal(lineIndex: Int, column: Int, left: Bool, right: Bool, style: StrokeStyle) {
        let center = point(lineIndex: lineIndex, column: column)
        var path = Path()
        path.move(to: CGPoint(x: left ? leftX(column: column) : center.x, y: center.y))
        path.addLine(to: CGPoint(x: right ? rightX(column: column) : center.x, y: center.y))
        context.stroke(path, with: .color(lineColor), style: style)
    }

    private mutating func drawCurve(lineIndex: Int, column: Int, from: Edge, to: Edge, style: StrokeStyle) {
        let center = point(lineIndex: lineIndex, column: column)
        let radius = JjGraphMetrics.cornerRadius
        var path = Path()
        switch (from, to) {
        case (.left, .bottom):
            path.move(to: CGPoint(x: leftX(column: column), y: center.y))
            path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
            path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: center)
            path.addLine(to: CGPoint(x: center.x, y: bottomY(lineIndex: lineIndex)))
        case (.bottom, .right):
            path.move(to: CGPoint(x: center.x, y: bottomY(lineIndex: lineIndex)))
            path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: center)
            path.addLine(to: CGPoint(x: rightX(column: column), y: center.y))
        case (.top, .left):
            path.move(to: CGPoint(x: center.x, y: topY(lineIndex: lineIndex)))
            path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
            path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: center)
            path.addLine(to: CGPoint(x: leftX(column: column), y: center.y))
        case (.top, .right):
            path.move(to: CGPoint(x: center.x, y: topY(lineIndex: lineIndex)))
            path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
            path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: center)
            path.addLine(to: CGPoint(x: rightX(column: column), y: center.y))
        default:
            return
        }
        context.stroke(path, with: .color(lineColor), style: style)
    }

    private mutating func drawElided(lineIndex: Int, column: Int, style: StrokeStyle) {
        let center = point(lineIndex: lineIndex, column: column)
        var path = Path()
        path.move(to: CGPoint(x: center.x - 3, y: center.y + 2))
        path.addQuadCurve(to: CGPoint(x: center.x + 3, y: center.y - 2), control: center)
        context.stroke(path, with: .color(lineSoftColor), style: style)
    }

    private func connectsAbove(lineIndex: Int, column: Int) -> Bool {
        guard lineIndex > 0 else { return false }
        guard let glyph = layout.lines[lineIndex - 1].cells.first(where: { $0.column == column })?.glyph else { return false }
        return glyph.connectsDown
    }

    private func connectsBelow(lineIndex: Int, column: Int) -> Bool {
        guard lineIndex + 1 < layout.lines.count else { return false }
        guard let glyph = layout.lines[lineIndex + 1].cells.first(where: { $0.column == column })?.glyph else { return false }
        return glyph.connectsUp
    }

    private func point(lineIndex: Int, column: Int) -> CGPoint {
        CGPoint(
            x: JjGraphMetrics.leftInset + CGFloat(column) * JjGraphMetrics.columnWidth,
            y: CGFloat(lineIndex) * JjGraphMetrics.lineHeight + JjGraphMetrics.lineHeight / 2
        )
    }

    private func topY(lineIndex: Int) -> CGFloat {
        max(0, CGFloat(lineIndex) * JjGraphMetrics.lineHeight)
    }

    private func bottomY(lineIndex: Int) -> CGFloat {
        min(size.height, CGFloat(lineIndex + 1) * JjGraphMetrics.lineHeight)
    }

    private func leftX(column: Int) -> CGFloat {
        max(0, JjGraphMetrics.leftInset + CGFloat(column - 1) * JjGraphMetrics.columnWidth)
    }

    private func rightX(column: Int) -> CGFloat {
        min(size.width, JjGraphMetrics.leftInset + CGFloat(column + 1) * JjGraphMetrics.columnWidth)
    }
}

private extension JjGraphGlyph {
    var connectsUp: Bool {
        switch self {
        case .vertical,
             .bendLeftUp,
             .bendRightUp,
             .horizontalUp,
             .verticalLeft,
             .verticalRight,
             .cross:
            return true
        case .empty,
             .horizontal,
             .ancestor,
             .bendLeftDown,
             .bendRightDown,
             .horizontalDown,
             .elided,
             .node,
             .unknown:
            return false
        }
    }

    var connectsDown: Bool {
        switch self {
        case .vertical,
             .ancestor,
             .bendLeftDown,
             .bendRightDown,
             .horizontalDown,
             .verticalLeft,
             .verticalRight,
             .cross:
            return true
        case .empty,
             .horizontal,
             .bendLeftUp,
             .bendRightUp,
             .horizontalUp,
             .elided,
             .node,
             .unknown:
            return false
        }
    }
}
