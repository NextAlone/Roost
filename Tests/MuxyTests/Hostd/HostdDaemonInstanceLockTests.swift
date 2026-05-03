import Foundation
import RoostHostdCore
import Testing

@Suite("HostdDaemonInstanceLock", .serialized)
struct HostdDaemonInstanceLockTests {
    @Test("lock rejects a second daemon for the same lock file")
    func lockRejectsSecondDaemon() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roost-hostd-lock-\(UUID().uuidString)")
        let lockURL = root.appendingPathComponent("daemon.lock", isDirectory: false)
        let lock = try HostdDaemonInstanceLock(url: lockURL)

        #expect(throws: HostdDaemonInstanceLockError.self) {
            try HostdDaemonInstanceLock(url: lockURL)
        }

        _ = lock
        try? FileManager.default.removeItem(at: root)
    }

    @Test("lock overwrites stale pid file")
    func lockOverwritesStalePIDFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roost-hostd-lock-\(UUID().uuidString)")
        let lockURL = root.appendingPathComponent("daemon.lock", isDirectory: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("999999\n".utf8).write(to: lockURL)

        let lock = try HostdDaemonInstanceLock(url: lockURL)

        let pid = try String(contentsOf: lockURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(pid == "\(getpid())")
        _ = lock
        try? FileManager.default.removeItem(at: root)
    }

    @Test("lock replaces stale legacy directory lock")
    func lockReplacesStaleLegacyDirectoryLock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roost-hostd-lock-\(UUID().uuidString)")
        let lockURL = root.appendingPathComponent("daemon.lock", isDirectory: false)
        try FileManager.default.createDirectory(at: lockURL, withIntermediateDirectories: true)
        try Data("999999\n".utf8).write(to: lockURL.appendingPathComponent("pid", isDirectory: false))

        let lock = try HostdDaemonInstanceLock(url: lockURL)

        let pid = try String(contentsOf: lockURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(pid == "\(getpid())")
        _ = lock
        try? FileManager.default.removeItem(at: root)
    }
}
