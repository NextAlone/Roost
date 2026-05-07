import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("ActivityLogStore")
struct ActivityLogStoreTests {
    @Test("append adds events in chronological order")
    func appendInOrder() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-log-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ActivityLogStore(fileURL: url, maxEvents: 1000)
        let paneID = UUID()
        store.append(AgentActivityEvent(paneID: paneID, to: .running))
        store.append(AgentActivityEvent(paneID: paneID, from: .running, to: .completed))

        #expect(store.events.count == 2)
        #expect(store.events.first?.to == .running)
        #expect(store.events.last?.to == .completed)
    }

    @Test("trims to maxEvents")
    func trimsToMax() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-log-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ActivityLogStore(fileURL: url, maxEvents: 2)
        let paneID = UUID()
        for _ in 0 ..< 5 {
            store.append(AgentActivityEvent(paneID: paneID, to: .running))
        }

        #expect(store.events.count == 2)
    }

    @Test("loads previously saved events on init")
    func loadsFromDisk() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-log-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = ActivityLogStore(fileURL: url, maxEvents: 1000)
        let paneID = UUID()
        first.append(AgentActivityEvent(paneID: paneID, to: .running))
        first.flush()

        let second = ActivityLogStore(fileURL: url, maxEvents: 1000)
        #expect(second.events.count == 1)
        #expect(second.events.first?.paneID == paneID)
    }

    @Test("eventsForPane filters by pane id")
    func eventsForPane() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-log-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = ActivityLogStore(fileURL: url, maxEvents: 1000)
        let paneA = UUID()
        let paneB = UUID()
        store.append(AgentActivityEvent(paneID: paneA, to: .running))
        store.append(AgentActivityEvent(paneID: paneB, to: .running))
        store.append(AgentActivityEvent(paneID: paneA, from: .running, to: .completed))

        let filtered = store.events(for: paneA)
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.paneID == paneA })
    }
}
