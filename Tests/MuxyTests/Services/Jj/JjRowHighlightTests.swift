import Testing

@testable import Roost

@Suite("JjRowHighlight")
struct JjRowHighlightTests {
    @Test("context target wins over hover")
    func contextTargetWinsOverHover() {
        #expect(JjRowHighlight.resolve(isHovered: true, isContextTarget: true) == .contextTarget)
    }

    @Test("hover highlights without context target")
    func hoverHighlightsWithoutContextTarget() {
        #expect(JjRowHighlight.resolve(isHovered: true, isContextTarget: false) == .hover)
    }

    @Test("no highlight when idle")
    func noHighlightWhenIdle() {
        #expect(JjRowHighlight.resolve(isHovered: false, isContextTarget: false) == .none)
    }
}
