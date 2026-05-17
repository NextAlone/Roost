import Foundation

public enum HostdStorage {
    #if DEV_MODE
    private static let hostdDirName = "hostd-dev"
    #else
    private static let hostdDirName = "hostd"
    #endif

    public static func defaultDatabaseURL() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return appSupport
            .appendingPathComponent("Roost", isDirectory: true)
            .appendingPathComponent(hostdDirName, isDirectory: true)
            .appendingPathComponent("sessions.sqlite", isDirectory: false)
    }

    public static func defaultDaemonLockURL() -> URL {
        defaultDatabaseURL()
            .deletingLastPathComponent()
            .appendingPathComponent("daemon.lock", isDirectory: false)
    }

    static func ensureParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
}
