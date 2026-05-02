import Testing

@testable import Roost

@Suite("ExpandedWorktreeRowLayout")
struct ExpandedWorktreeRowLayoutTests {
    @Test("workspace row reserves gutters for selection and trailing status")
    func workspaceRowReservesGutters() {
        #expect(ExpandedWorktreeRowLayout.leadingContentInset >= 22)
        #expect(ExpandedWorktreeRowLayout.leadingContentInset > ExpandedWorktreeRowLayout.selectedStripeWidth)
        #expect(ExpandedWorktreeRowLayout.trailingContentInset >= 8)
        #expect(ExpandedWorktreeRowLayout.minContentHeight >= ExpandedWorktreeRowLayout.statusDotHeight)
    }
}
