import Foundation

enum MuxyFileStorage {
    static func fileURL(filename: String) -> URL {
        let dir = appSupportDirectory()
        return dir.appendingPathComponent(filename)
    }

    static func appSupportDirectory() -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        else {
            fatalError("Application Support directory unavailable")
        }
        return appSupportDirectory(baseDirectory: appSupport)
    }

    static func appSupportDirectory(baseDirectory: URL) -> URL {
        let dir = baseDirectory.appendingPathComponent("Roost", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: FilePermissions.privateDirectory]
        )
        return dir
    }

    static func worktreeRoot(forProjectID projectID: UUID) -> URL {
        let dir = appSupportDirectory()
            .appendingPathComponent("worktree-checkouts", isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: FilePermissions.privateDirectory]
        )
        return dir
    }

    static func worktreeDirectory(forProjectID projectID: UUID, name: String) -> URL {
        worktreeRoot(forProjectID: projectID).appendingPathComponent(name, isDirectory: true)
    }
}
