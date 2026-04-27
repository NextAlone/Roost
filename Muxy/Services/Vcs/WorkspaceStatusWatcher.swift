import CoreServices
import Foundation
import MuxyShared

final class WorkspaceStatusWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.roost.workspace-status-watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var debounceWork: DispatchWorkItem?
    private let handler: @Sendable () -> Void

    init?(directoryPath: String, vcsKind: VcsKind, handler: @escaping @Sendable () -> Void) {
        let metaDir: String
        switch vcsKind {
        case .git: metaDir = ".git"
        case .jj: metaDir = ".jj"
        }
        let metaPath = (directoryPath as NSString).appendingPathComponent(metaDir)
        guard FileManager.default.fileExists(atPath: metaPath) else { return nil }

        self.handler = handler

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let paths = [directoryPath] as CFArray
        guard let stream = FSEventStreamCreate(
            nil,
            { _, clientInfo, numEvents, _, _, _ in
                guard let clientInfo, numEvents > 0 else { return }
                let watcher = Unmanaged<WorkspaceStatusWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
                watcher.scheduleRefresh()
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        else { return nil }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        debounceWork?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func scheduleRefresh() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.handler()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
