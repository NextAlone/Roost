import Testing

@testable import Roost

@Suite("Help links")
struct HelpLinksTests {
    @Test("help links point at Roost resources")
    func helpLinksPointAtRoostResources() {
        #expect(HelpLinks.repoDisplayName == "NextAlone/Roost")

        let urls = [
            HelpLinks.repoURL.absoluteString,
            HelpLinks.docsURL.absoluteString,
            HelpLinks.issuesURL.absoluteString,
        ]

        for url in urls {
            #expect(!url.contains("muxy-app"))
            #expect(url.contains("NextAlone/Roost"))
        }
    }
}
