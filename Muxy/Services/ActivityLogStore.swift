import Foundation
import MuxyShared
import os

private let logger = Logger(subsystem: "app.muxy", category: "ActivityLogStore")

@MainActor
protocol ActivityLogStoring: AnyObject {
    func append(_ event: AgentActivityEvent)
}

@MainActor
@Observable
final class ActivityLogStore: ActivityLogStoring {
    private(set) var events: [AgentActivityEvent] = []

    private let store: CodableFileStore<[AgentActivityEvent]>
    private let maxEvents: Int
    private var saveTask: Task<Void, Never>?

    static let defaultFileURL: URL = MuxyFileStorage.fileURL(filename: "activity-log.json")
    static let defaultMaxEvents = 1000

    init(
        fileURL: URL = ActivityLogStore.defaultFileURL,
        maxEvents: Int = ActivityLogStore.defaultMaxEvents
    ) {
        self.store = CodableFileStore<[AgentActivityEvent]>(fileURL: fileURL)
        self.maxEvents = maxEvents
        self.events = Self.loadFromDisk(store: store, maxEvents: maxEvents)
    }

    func append(_ event: AgentActivityEvent) {
        events.append(event)
        trim()
        scheduleSave()
    }

    func events(for paneID: UUID) -> [AgentActivityEvent] {
        events.filter { $0.paneID == paneID }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        saveToDisk()
    }

    private func trim() {
        guard events.count > maxEvents else { return }
        events = Array(events.suffix(maxEvents))
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveToDisk()
        }
    }

    private func saveToDisk() {
        do {
            try store.save(events)
        } catch {
            logger.error("Failed to save activity log: \(error.localizedDescription)")
        }
    }

    private static func loadFromDisk(
        store: CodableFileStore<[AgentActivityEvent]>,
        maxEvents: Int
    ) -> [AgentActivityEvent] {
        do {
            let loaded = try store.load() ?? []
            return Array(loaded.suffix(maxEvents))
        } catch {
            logger.error("Failed to load activity log: \(error.localizedDescription)")
            return []
        }
    }
}
