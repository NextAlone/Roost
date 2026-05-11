import Testing

@testable import Roost

@Suite("ExpandedWorktreeRowLayout")
struct ExpandedWorktreeRowLayoutTests {
    @Test("workspace row reserves gutters for selection and trailing status")
    func workspaceRowReservesGutters() {
        #expect(ExpandedWorktreeRowLayout.leadingContentInset >= 20)
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
        #expect(ExpandedWorktreeRowLayout.worktreeLeadingContentInset == 20)
        #expect(ExpandedWorktreeRowLayout.worktreeMarkerWidth <= 20)
        #expect(ExpandedWorktreeRowLayout.worktreeTitleLeadingEdge == 44)
        #expect(ExpandedWorktreeRowLayout.projectTitleLeadingEdge == 36)
    }

    @Test("project rows match expanded add project sizing")
    func projectRowsMatchExpandedAddProjectSizing() {
        #expect(ExpandedWorktreeRowLayout.projectRowMinHeight == AddProjectButtonLayout.expandedRowHeight)
        #expect(ExpandedWorktreeRowLayout.projectIconSize == AddProjectButtonLayout.expandedIconSize)
        #expect(ExpandedWorktreeRowLayout.projectLeadingContentInset == AddProjectButtonLayout.expandedLeadingContentInset)
        #expect(ExpandedWorktreeRowLayout.projectColumnSpacing == AddProjectButtonLayout.expandedColumnSpacing)
        #expect(ExpandedWorktreeRowLayout.trailingContentInset == AddProjectButtonLayout.expandedTrailingContentInset)
    }

    @Test("expanded scratch row matches project row geometry")
    func expandedScratchRowMatchesProjectRowGeometry() {
        #expect(ScratchRowLayout.expandedOuterHorizontalInset == SidebarLayout.expandedProjectListHorizontalInset)
        #expect(ScratchRowLayout.expandedContentLeadingInset == ExpandedWorktreeRowLayout.projectLeadingContentInset)
        #expect(ScratchRowLayout.expandedContentTrailingInset == ExpandedWorktreeRowLayout.trailingContentInset)
        #expect(ScratchRowLayout.expandedIconSize == ExpandedWorktreeRowLayout.projectIconSize)
        #expect(ScratchRowLayout.expandedMinHeight == ExpandedWorktreeRowLayout.projectRowMinHeight)
        #expect(ScratchRowLayout.expandedVerticalPadding == ExpandedWorktreeRowLayout.projectVerticalPadding)
    }

    @Test("pending agent summary is compact utility instead of project row")
    func pendingAgentSummaryIsCompactUtility() {
        #expect(PendingAgentsBannerLayout.horizontalInset == ExpandedWorktreeRowLayout.projectTitleLeadingEdge)
        #expect(PendingAgentsBannerLayout.verticalPadding < ExpandedWorktreeRowLayout.projectVerticalPadding)
        #expect(PendingAgentsBannerLayout.dotSize < AgentActivityStatusBadgeLayout.diameter)
    }

    @Test("top fixed bar and project list do not create a dead gap")
    func topFixedBarAndProjectListDoNotCreateDeadGap() {
        #expect(SidebarLayout.topFixedBarBottomPadding == 0)
        #expect(SidebarLayout.projectListTopPadding == 0)
        #expect(SidebarLayout.topFixedBarBottomPadding + SidebarLayout.projectListTopPadding == 0)
    }

    @Test("default project letter stays readable")
    func defaultProjectLetterStaysReadable() {
        #expect(ExpandedWorktreeRowLayout.projectLetterFontSize >= 13)
        #expect(ExpandedWorktreeRowLayout.projectLetterFontSize < ExpandedWorktreeRowLayout.projectIconSize)
    }
}
