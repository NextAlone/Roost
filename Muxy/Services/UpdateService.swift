import Combine
import Foundation
import os
#if !DEV_MODE
import Sparkle
#endif

private let logger = Logger(subsystem: "app.muxy", category: "UpdateService")

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    static let storageKey = "muxy.update.channel"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stable: "Stable"
        case .beta: "Beta"
        }
    }

    var feedURL: String {
        switch self {
        case .stable:
            ""
        case .beta:
            ""
        }
    }

    var hasConfiguredFeed: Bool {
        !feedURL.isEmpty
    }

    private static var archSlug: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}

@MainActor @Observable
final class UpdateService: NSObject {
    static let shared = UpdateService()

    #if !DEV_MODE
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private let feedDelegate: FeedDelegate

    private var updater: SPUUpdater {
        controller.updater
    }
    #endif

    private(set) var canCheckForUpdates = false
    private(set) var availableUpdateVersion: String?

    var channel: UpdateChannel {
        get { storedChannel }
        set {
            guard newValue != storedChannel else { return }
            storedChannel = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: UpdateChannel.storageKey)
            availableUpdateVersion = nil
            #if !DEV_MODE
            if newValue.hasConfiguredFeed {
                updater.checkForUpdatesInBackground()
            }
            #endif
        }
    }

    private var storedChannel: UpdateChannel

    override private init() {
        let stored = UserDefaults.standard.string(forKey: UpdateChannel.storageKey)
            .flatMap { UpdateChannel(rawValue: $0) } ?? .stable
        storedChannel = stored
        #if !DEV_MODE
        let delegate = FeedDelegate(channel: stored)
        feedDelegate = delegate
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        super.init()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: \.canCheckForUpdates, on: self)
            .store(in: &cancellables)
        observeUpdateNotifications()
        #else
        super.init()
        #endif
        applyFeatureFlags()
    }

    func start() {
        #if !DEV_MODE
        guard feedDelegate.channel.hasConfiguredFeed else {
            canCheckForUpdates = false
            return
        }
        do {
            try updater.start()
        } catch {
            logger.warning("Sparkle updater failed to start: \(error.localizedDescription)")
        }
        #endif
    }

    func checkForUpdates() {
        #if !DEV_MODE
        guard feedDelegate.channel.hasConfiguredFeed else { return }
        controller.checkForUpdates(nil)
        #endif
    }

    private func applyFeatureFlags() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["FF_UPDATE_AVAILABLE"] != nil {
            availableUpdateVersion = "0.0.0-dev"
        }
        #endif
    }

    #if !DEV_MODE
    private func observeUpdateNotifications() {
        NotificationCenter.default.publisher(for: .SUUpdaterDidFindValidUpdate)
            .compactMap { $0.userInfo?[SUUpdaterAppcastItemNotificationKey] as? SUAppcastItem }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.availableUpdateVersion = item.displayVersionString
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .SUUpdaterDidNotFindUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.availableUpdateVersion = nil
            }
            .store(in: &cancellables)
    }
    #endif
}

#if !DEV_MODE
private final class FeedDelegate: NSObject, SPUUpdaterDelegate {
    var channel: UpdateChannel

    init(channel: UpdateChannel) {
        self.channel = channel
        super.init()
    }

    func feedURLString(for _: SPUUpdater) -> String? {
        channel.feedURL.isEmpty ? nil : channel.feedURL
    }

    func allowedChannels(for _: SPUUpdater) -> Set<String> {
        switch channel {
        case .stable: []
        case .beta: [channel.rawValue]
        }
    }
}
#endif
