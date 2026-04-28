import Foundation
import MuxyShared

enum RoostConfigStore {
    static let securePermissions = 0o600
    static let directoryPermissions = 0o700

    static func configURL(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent(".roost", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    static func load(projectPath: String) throws -> RoostConfig? {
        let url = configURL(projectPath: projectPath)
        let store = CodableFileStore<RoostConfig>(fileURL: url)
        return try store.load()
    }

    static func save(_ config: RoostConfig, projectPath: String) throws {
        let url = configURL(projectPath: projectPath)
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

    static func fileSecurity(projectPath: String) -> RoostConfigFileSecurity {
        let url = configURL(projectPath: projectPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let permissions = permissions(url: url) else { return .unknown }
        return permissions & 0o077 == 0 ? .secure : .tooPermissive(permissions: permissions)
    }

    static func enforceSecurePermissions(projectPath: String) throws {
        let url = configURL(projectPath: projectPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.setAttributes([.posixPermissions: securePermissions], ofItemAtPath: url.path)
    }

    private static func permissions(url: URL) -> Int? {
        guard let value = try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber else {
            return nil
        }
        return value.intValue
    }
}

enum RoostConfigFileSecurity: Equatable {
    case missing
    case secure
    case tooPermissive(permissions: Int)
    case unknown
}
