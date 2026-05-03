import CoreGraphics
import SwiftUI

struct HostdOwnedTerminalGrid: Equatable {
    let columns: UInt16
    let rows: UInt16
}

enum HostdOwnedTerminalGridCalculator {
    static let defaultCellSize = CGSize(width: 7.25, height: 15)
    static let defaultHorizontalPadding: CGFloat = 28
    static let defaultVerticalPadding: CGFloat = 28

    static func grid(
        for size: CGSize,
        cellSize: CGSize = defaultCellSize,
        horizontalPadding: CGFloat = defaultHorizontalPadding,
        verticalPadding: CGFloat = defaultVerticalPadding
    ) -> HostdOwnedTerminalGrid? {
        guard size.width > 0,
              size.height > 0,
              cellSize.width > 0,
              cellSize.height > 0
        else { return nil }

        let availableWidth = max(size.width - horizontalPadding, 0)
        let availableHeight = max(size.height - verticalPadding, 0)
        let columns = boundedUInt16(Int(floor(availableWidth / cellSize.width)), minimum: 2)
        let rows = boundedUInt16(Int(floor(availableHeight / cellSize.height)), minimum: 1)
        return HostdOwnedTerminalGrid(columns: columns, rows: rows)
    }

    private static func boundedUInt16(_ value: Int, minimum: Int) -> UInt16 {
        UInt16(max(minimum, min(value, Int(UInt16.max))))
    }
}

struct HostdOwnedTerminalResizeReporter: View {
    let clientAvailable: Bool
    let onResize: (CGSize) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    onResize(proxy.size)
                }
                .onChange(of: proxy.size) { _, size in
                    onResize(size)
                }
                .onChange(of: clientAvailable) { _, _ in
                    onResize(proxy.size)
                }
        }
        .allowsHitTesting(false)
    }
}
