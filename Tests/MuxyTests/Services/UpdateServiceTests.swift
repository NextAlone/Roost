import Testing

@testable import Roost

@Suite("UpdateService")
struct UpdateServiceTests {
    @Test("update feeds do not point to upstream Muxy")
    func updateFeedsDoNotPointToUpstreamMuxy() {
        for channel in UpdateChannel.allCases {
            #expect(!channel.feedURL.contains("github.com/muxy-app/muxy"))
            #expect(channel.feedURL.isEmpty || channel.feedURL.contains("roost"))
        }
    }
}
