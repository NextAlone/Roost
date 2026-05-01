import Testing

@testable import Roost

@Suite("JjConflictMarkerParser")
struct JjConflictMarkerParserTests {
    @Test("parses jj diff style conflict markers")
    func parsesJjDiffStyleMarkers() {
        let text = #"""
        <<<<<<< conflict 1 of 1
        %%%%%%% diff from: rosxkstz 4c9d7042 "base"
        \\\\\\\        to: smuwwqor 279412a7 "left"
        -base
        +left
        +left extra
        +++++++ mxlvylml 8f4311f4 "right"
        right
        >>>>>>> conflict 1 of 1 ends
        """#

        let preview = JjConflictMarkerParser.parse(text)

        #expect(preview.regions.count == 1)
        #expect(preview.regions[0].base == "base")
        #expect(preview.regions[0].current == "left\nleft extra")
        #expect(preview.regions[0].incoming == "right")
    }

    @Test("parses git diff3 style conflict markers")
    func parsesGitDiff3StyleMarkers() {
        let text = """
        before
        <<<<<<< ours
        current
        ||||||| base
        base
        =======
        incoming
        >>>>>>> theirs
        after
        """

        let preview = JjConflictMarkerParser.parse(text)

        #expect(preview.regions.count == 1)
        #expect(preview.regions[0].base == "base")
        #expect(preview.regions[0].current == "current")
        #expect(preview.regions[0].incoming == "incoming")
    }

    @Test("ignores content without conflict markers")
    func ignoresContentWithoutMarkers() {
        let preview = JjConflictMarkerParser.parse("plain text")

        #expect(preview.regions.isEmpty)
    }

    @Test("builds resolved content with edited regions")
    func buildsResolvedContent() {
        let text = """
        before
        <<<<<<< ours
        current
        ||||||| base
        base
        =======
        incoming
        >>>>>>> theirs
        after
        """

        let preview = JjConflictMarkerParser.parse(text)
        let resolved = preview.resolvedText(replacements: [1: "merged"])

        #expect(resolved == "before\nmerged\nafter")
    }
}
