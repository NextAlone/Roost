import CoreGraphics
import Foundation
import Testing

@testable import Roost

@Suite("HostdOwnedTerminalGridCalculator")
struct HostdOwnedTerminalGridCalculatorTests {
    @Test("calculates grid from pane size")
    func calculatesGridFromPaneSize() {
        let grid = HostdOwnedTerminalGridCalculator.grid(
            for: CGSize(width: 160, height: 80),
            cellSize: CGSize(width: 8, height: 16),
            horizontalPadding: 0,
            verticalPadding: 0
        )

        #expect(grid == HostdOwnedTerminalGrid(columns: 20, rows: 5))
    }

    @Test("applies padding and minimum grid")
    func appliesPaddingAndMinimumGrid() {
        let grid = HostdOwnedTerminalGridCalculator.grid(
            for: CGSize(width: 40, height: 40),
            cellSize: CGSize(width: 20, height: 20),
            horizontalPadding: 30,
            verticalPadding: 30
        )

        #expect(grid == HostdOwnedTerminalGrid(columns: 2, rows: 1))
    }

    @Test("rejects invalid sizes")
    func rejectsInvalidSizes() {
        #expect(HostdOwnedTerminalGridCalculator.grid(
            for: CGSize(width: 0, height: 80),
            cellSize: CGSize(width: 8, height: 16)
        ) == nil)
        #expect(HostdOwnedTerminalGridCalculator.grid(
            for: CGSize(width: 160, height: 80),
            cellSize: CGSize(width: 0, height: 16)
        ) == nil)
    }
}
