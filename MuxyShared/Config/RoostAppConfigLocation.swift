import Foundation

public enum RoostAppConfigLocation {
    public static func configURL() -> URL {
        configURL(baseDirectory: appSupportBaseDirectory())
    }

    public static func configURL(baseDirectory: URL) -> URL {
        baseDirectory
            .appendingPathComponent("Roost", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private static func appSupportBaseDirectory() -> URL {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        return url
    }
}
