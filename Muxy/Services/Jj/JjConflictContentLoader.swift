import Foundation

struct JjConflictContent: Equatable, Identifiable, Sendable {
    let path: String
    let text: String

    var id: String { path }
}

enum JjConflictContentLoaderError: Error, Equatable {
    case absolutePath
    case pathEscapesRepository
    case fileTooLarge
    case invalidUTF8
}

struct JjConflictContentLoader: Sendable {
    private let maxBytes: Int

    init(maxBytes: Int = 512 * 1024) {
        self.maxBytes = maxBytes
    }

    func load(repoPath: String, path: String) async throws -> JjConflictContent {
        let fileURL = try JjConflictContentFile.fileURL(repoPath: repoPath, path: path)

        let maxBytes = self.maxBytes
        let data = try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: fileURL)
            guard data.count <= maxBytes else { throw JjConflictContentLoaderError.fileTooLarge }
            return data
        }.value

        guard let text = String(data: data, encoding: .utf8) else {
            throw JjConflictContentLoaderError.invalidUTF8
        }

        return JjConflictContent(path: path, text: text)
    }
}

struct JjConflictContentWriter: Sendable {
    func write(repoPath: String, path: String, text: String) async throws {
        let fileURL = try JjConflictContentFile.fileURL(repoPath: repoPath, path: path)
        let data = Data(text.utf8)
        try await Task.detached(priority: .userInitiated) {
            try data.write(to: fileURL, options: .atomic)
        }.value
    }
}

private enum JjConflictContentFile {
    static func fileURL(repoPath: String, path: String) throws -> URL {
        guard !path.hasPrefix("/") else { throw JjConflictContentLoaderError.absolutePath }

        let repoURL = URL(fileURLWithPath: repoPath).standardizedFileURL.resolvingSymlinksInPath()
        let fileURL = repoURL.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        let repoPrefix = repoURL.path.hasSuffix("/") ? repoURL.path : repoURL.path + "/"

        guard fileURL.path.hasPrefix(repoPrefix) else {
            throw JjConflictContentLoaderError.pathEscapesRepository
        }

        return fileURL
    }
}
