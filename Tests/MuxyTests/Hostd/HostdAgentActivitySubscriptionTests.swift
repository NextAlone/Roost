import Foundation
import MuxyShared
import RoostHostdCore
import Testing

@testable import RoostHostdCore

@Suite("HostdAgentActivitySubscription")
struct HostdAgentActivitySubscriptionTests {
    private func makeTempStoreURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-tests")
            .appendingPathComponent(UUID().uuidString)
        return tmp.appendingPathComponent("sessions.sqlite")
    }

    @Test("subscription yields confirmed state transitions and skips duplicates")
    func subscriptionYieldsConfirmedTransitions() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let paneID = UUID()
        let sessionName = HostdTmuxSessionName.name(for: paneID)
        let mock = ScriptedTmux(sessionName: sessionName, screens: [
            workingScreen, workingScreen, workingScreen,
            idleScreen, idleScreen, idleScreen,
        ])
        let registry = HostdProcessRegistry(store: store, tmux: mock)

        let stream = await registry.subscribeAgentActivity(subscriptions: [paneID: "claude"])
        let collected: [AgentDetectionState] = await {
            var out: [AgentDetectionState] = []
            for await event in stream {
                out.append(event.detection.state)
                if out.count >= 2 { break }
            }
            return out
        }()

        #expect(collected == [.working, .idle])
    }

    @Test("subscription stops detection loop when last subscriber disconnects")
    func subscriptionStopsLoopWhenLastSubscriberGone() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try await SessionStore(url: url)
        let paneID = UUID()
        let sessionName = HostdTmuxSessionName.name(for: paneID)
        let mock = ScriptedTmux(sessionName: sessionName, screens: Array(repeating: workingScreen, count: 100))
        let registry = HostdProcessRegistry(store: store, tmux: mock)

        do {
            let stream = await registry.subscribeAgentActivity(subscriptions: [paneID: "claude"])
            var iter = stream.makeAsyncIterator()
            _ = await iter.next()
        }

        for _ in 0 ..< 50 {
            if await mock.captureCalls == 0 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
            await mock.resetCounter()
        }
        let baseline = await mock.captureCalls
        try await Task.sleep(nanoseconds: 800_000_000)
        let afterCancel = await mock.captureCalls
        #expect(afterCancel - baseline <= 1)
    }
}

private let workingScreen = """

  ✻ Doing work… (esc to interrupt)

"""

private let idleScreen = """

>
⌐ Search anywhere…   ⌐ Ctrl+R to toggle

"""

private actor ScriptedTmux: HostdTmuxControlling {
    private let sessionName: String
    private var screens: [String]
    private var index = 0
    private(set) var captureCalls = 0

    init(sessionName: String, screens: [String]) {
        self.sessionName = sessionName
        self.screens = screens
    }

    func resetCounter() { captureCalls = 0 }

    func launch(sessionName _: String, workspacePath _: String, command _: String, environment _: [String: String]) async throws {}
    func hasSession(named name: String) async -> Bool { name == sessionName }
    func killSession(named _: String) async throws {}
    func isPaneDead(sessionName _: String) async -> Bool { false }
    func sendKeys(sessionName _: String, keys _: String) async throws {}

    func captureLastTail(sessionName _: String, lines _: Int) async -> String? {
        captureCalls += 1
        guard !screens.isEmpty else { return screens.last }
        let screen = screens[min(index, screens.count - 1)]
        if index < screens.count - 1 { index += 1 }
        return screen
    }
}
