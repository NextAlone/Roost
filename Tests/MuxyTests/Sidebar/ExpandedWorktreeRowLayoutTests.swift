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

    @Test("tree rows share the same marker and title columns")
    func treeRowsShareColumns() {
        #expect(ExpandedWorktreeRowLayout.worktreeMarkerWidth == ExpandedWorktreeRowLayout.newWorktreeMarkerWidth)
        #expect(ExpandedWorktreeRowLayout.worktreeLeadingContentInset == ExpandedWorktreeRowLayout.newWorktreeLeadingContentInset)
        #expect(ExpandedWorktreeRowLayout.worktreeTitleLeadingEdge == ExpandedWorktreeRowLayout.newWorktreeTitleLeadingEdge)
        #expect(ExpandedWorktreeRowLayout.worktreeTitleLeadingEdge > ExpandedWorktreeRowLayout.projectTitleLeadingEdge)
    }

    @Test("compact tree rows keep stable heights")
    func compactTreeRowsKeepStableHeights() {
        #expect(ExpandedWorktreeRowLayout.projectRowMinHeight >= ExpandedWorktreeRowLayout.worktreeRowMinHeight)
        #expect(ExpandedWorktreeRowLayout.worktreeRowMinHeight == ExpandedWorktreeRowLayout.newWorktreeRowMinHeight)
        #expect(ExpandedWorktreeRowLayout.worktreeRowMinHeight > ExpandedWorktreeRowLayout.statusDotHeight)
    }

    @Test("dense tree layout avoids sparse gutters")
    func denseTreeLayoutAvoidsSparseGutters() {
        #expect(ExpandedWorktreeRowLayout.projectRowMinHeight <= 40)
        #expect(ExpandedWorktreeRowLayout.worktreeRowMinHeight <= 30)
        #expect(ExpandedWorktreeRowLayout.worktreeLeadingContentInset <= 28)
        #expect(ExpandedWorktreeRowLayout.worktreeMarkerWidth <= 20)
        #expect(ExpandedWorktreeRowLayout.worktreeTitleLeadingEdge <= 56)
        #expect(ExpandedWorktreeRowLayout.projectTitleLeadingEdge <= 52)
    }

    @Test("project rows match expanded add project sizing")
    func projectRowsMatchExpandedAddProjectSizing() {
        #expect(ExpandedWorktreeRowLayout.projectRowMinHeight == AddProjectButtonLayout.expandedRowHeight)
        #expect(ExpandedWorktreeRowLayout.projectIconSize == AddProjectButtonLayout.expandedIconSize)
        #expect(ExpandedWorktreeRowLayout.projectLeadingContentInset == AddProjectButtonLayout.expandedLeadingContentInset)
        #expect(ExpandedWorktreeRowLayout.projectColumnSpacing == AddProjectButtonLayout.expandedColumnSpacing)
        #expect(ExpandedWorktreeRowLayout.trailingContentInset == AddProjectButtonLayout.expandedTrailingContentInset)
    }

    @Test("default project letter stays readable")
    func defaultProjectLetterStaysReadable() {
        #expect(ExpandedWorktreeRowLayout.projectLetterFontSize >= 13)
        #expect(ExpandedWorktreeRowLayout.projectLetterFontSize < ExpandedWorktreeRowLayout.projectIconSize)
    }
}
