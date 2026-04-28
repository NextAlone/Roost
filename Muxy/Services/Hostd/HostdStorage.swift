import Foundation

enum HostdStorage {
    static func defaultDatabaseURL() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return appSupport
            .appendingPathComponent("Roost", isDirectory: true)
            .appendingPathComponent("hostd", isDirectory: true)
            .appendingPathComponent("sessions.sqlite", isDirectory: false)
    }

    static func ensureParentDirectory(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
}
