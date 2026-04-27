import CoreServices
import Foundation
import MuxyShared

final class VcsDirectoryWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.muxy.vcs-watcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var debounceWork: DispatchWorkItem?
    private var handler: (@Sendable () -> Void)?
    private let vcsKind: VcsKind
    private let metaPathCanonical: String

    init?(directoryPath: String, vcsKind: VcsKind = .git, handler: @escaping @Sendable () -> Void) {
        let metaDir: String
        switch vcsKind {
        case .git:
            metaDir = ".git"
        case .jj:
            metaDir = ".jj"
        }
        let metaPath = (directoryPath as NSString).appendingPathComponent(metaDir)
        guard FileManager.default.fileExists(atPath: metaPath) else { return nil }

        self.handler = handler
        self.vcsKind = vcsKind
        self.metaPathCanonical = URL(fileURLWithPath: metaPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let paths = [directoryPath] as CFArray
        guard let stream = FSEventStreamCreate(
            nil,
            { _, clientInfo, numEvents, eventPaths, eventFlags, _ in
                guard let clientInfo, numEvents > 0 else { return }
                let watcher = Unmanaged<VcsDirectoryWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
                guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String]
                else { return }
                let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

                let dominated = zip(paths, flags).allSatisfy { path, flag in
                    watcher.isNoise(path: path, flag: flag)
                }
                guard !dominated else { return }

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
        handler = nil
        debounceWork?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func isNoise(path: String, flag: UInt32) -> Bool {
        let isDir = flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
        let canonical = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        guard canonical.hasPrefix(metaPathCanonical + "/") || canonical == metaPathCanonical else {
            return false
        }
        switch vcsKind {
        case .git:
            let isLockFile = path.hasSuffix(".lock")
            return isLockFile || isDir
        case .jj:
            return true
        }
    }

    private func scheduleRefresh() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.handler?()
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
