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
        if case .elided = glyph {
            drawElided(lineIndex: lineIndex, column: column, style: style)
            return
        }

        let edges = glyph.edges
        guard !edges.isEmpty else { return }
        if drawCorner(edges: edges, lineIndex: lineIndex, column: column, style: style) {
            return
        }
        drawStraightEdges(edges, lineIndex: lineIndex, column: column, style: style)
    }

    private mutating func drawNode(_ glyph: JjGraphGlyph, lineIndex: Int, column: Int, style: StrokeStyle) {
        guard case let .node(label) = glyph else { return }
        let center = point(lineIndex: lineIndex, column: column)
        let radius = JjGraphMetrics.nodeRadius

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

    private mutating func drawStraightEdges(
        _ edges: JjGraphGlyphEdges,
        lineIndex: Int,
        column: Int,
        style: StrokeStyle
    ) {
        let center = point(lineIndex: lineIndex, column: column)
        var path = Path()

        if edges.contains(.top) {
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x, y: topY(lineIndex: lineIndex)))
        }
        if edges.contains(.bottom) {
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x, y: bottomY(lineIndex: lineIndex)))
        }
        if edges.contains(.left) {
            path.move(to: center)
            path.addLine(to: CGPoint(x: leftX(column: column), y: center.y))
        }
        if edges.contains(.right) {
            path.move(to: center)
            path.addLine(to: CGPoint(x: rightX(column: column), y: center.y))
        }

        context.stroke(path, with: .color(lineColor), style: style)
    }

    private mutating func drawCorner(
        edges: JjGraphGlyphEdges,
        lineIndex: Int,
        column: Int,
        style: StrokeStyle
    ) -> Bool {
        let center = point(lineIndex: lineIndex, column: column)
        let radius = JjGraphMetrics.cornerRadius
        var path = Path()
        switch edges {
        case [.left, .bottom]:
            path.move(to: CGPoint(x: leftX(column: column), y: center.y))
            path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
            path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: center)
            path.addLine(to: CGPoint(x: center.x, y: bottomY(lineIndex: lineIndex)))
        case [.right, .bottom]:
            path.move(to: CGPoint(x: center.x, y: bottomY(lineIndex: lineIndex)))
            path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: center)
            path.addLine(to: CGPoint(x: rightX(column: column), y: center.y))
        case [.top, .left]:
            path.move(to: CGPoint(x: center.x, y: topY(lineIndex: lineIndex)))
            path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
            path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: center)
            path.addLine(to: CGPoint(x: leftX(column: column), y: center.y))
        case [.top, .right]:
            path.move(to: CGPoint(x: center.x, y: topY(lineIndex: lineIndex)))
            path.addLine(to: CGPoint(x: center.x, y: center.y - radius))
            path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: center)
            path.addLine(to: CGPoint(x: rightX(column: column), y: center.y))
        default:
            return false
        }
        context.stroke(path, with: .color(lineColor), style: style)
        return true
    }

    private mutating func drawElided(lineIndex: Int, column: Int, style: StrokeStyle) {
        let center = point(lineIndex: lineIndex, column: column)
        var path = Path()
        path.move(to: CGPoint(x: center.x - 3, y: center.y + 2))
        path.addQuadCurve(to: CGPoint(x: center.x + 3, y: center.y - 2), control: center)
        context.stroke(path, with: .color(lineSoftColor), style: style)
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
        max(0, JjGraphMetrics.leftInset + CGFloat(column) * JjGraphMetrics.columnWidth - JjGraphMetrics.columnWidth / 2)
    }

    private func rightX(column: Int) -> CGFloat {
        min(size.width, JjGraphMetrics.leftInset + CGFloat(column) * JjGraphMetrics.columnWidth + JjGraphMetrics.columnWidth / 2)
    }
}
