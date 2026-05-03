import Foundation
import MuxyShared

enum RoostAppConfigStore {
    static let securePermissions = 0o600
    static let directoryPermissions = 0o700

    static func configURL() -> URL {
        RoostAppConfigLocation.configURL()
    }

    static func configURL(baseDirectory: URL) -> URL {
        RoostAppConfigLocation.configURL(baseDirectory: baseDirectory)
    }

    static func load() throws -> RoostConfig? {
        try load(baseDirectory: appSupportBaseDirectory())
    }

    static func load(baseDirectory: URL) throws -> RoostConfig? {
        let store = CodableFileStore<RoostConfig>(fileURL: configURL(baseDirectory: baseDirectory))
        return try store.load()
    }

    static func save(_ config: RoostConfig) throws {
        try save(config, baseDirectory: appSupportBaseDirectory())
    }

    static func save(_ config: RoostConfig, baseDirectory: URL) throws {
        let url = configURL(baseDirectory: baseDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions]
        )
        let store = CodableFileStore<RoostConfig>(
            fileURL: url,
            options: CodableFileStoreOptions(
                prettyPrinted: true,
                sortedKeys: true,
                filePermissions: securePermissions
            )
        )
        try store.save(config)
    }

    static func fileSecurity() -> RoostConfigFileSecurity {
        fileSecurity(baseDirectory: appSupportBaseDirectory())
    }

    static func fileSecurity(baseDirectory: URL) -> RoostConfigFileSecurity {
        let url = configURL(baseDirectory: baseDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let permissions = permissions(url: url) else { return .unknown }
        return permissions & 0o077 == 0 ? .secure : .tooPermissive(permissions: permissions)
    }

    static func enforceSecurePermissions() throws {
        try enforceSecurePermissions(baseDirectory: appSupportBaseDirectory())
    }

    static func enforceSecurePermissions(baseDirectory: URL) throws {
        let url = configURL(baseDirectory: baseDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.setAttributes([.posixPermissions: securePermissions], ofItemAtPath: url.path)
    }

    private static func appSupportBaseDirectory() -> URL {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        return url
    }

    private static func permissions(url: URL) -> Int? {
        guard let value = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber else {
            return nil
        }
        return value.intValue
    }
}
