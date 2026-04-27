import Foundation

actor JjProcessQueue {
    static let shared = JjProcessQueue()

    private var inflight: [String: Task<Void, Never>] = [:]

    init() {}

    func run<T: Sendable>(
        repoPath: String,
        isMutating: Bool,
        body: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        if !isMutating {
            return try await body()
        }
        let key = Self.canonicalKey(for: repoPath)
        let previous = inflight[key]
        let resultBox = ResultBox<T>()
        let task = Task {
            await previous?.value
            do {
                let value = try await body()
                await resultBox.set(.success(value))
            } catch {
                await resultBox.set(.failure(error))
            }
        }
        inflight[key] = task
        await task.value
        if inflight[key] == task {
            inflight[key] = nil
        }
        return try await resultBox.value()
    }

    static func canonicalKey(for repoPath: String) -> String {
        URL(fileURLWithPath: repoPath).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

private actor ResultBox<T: Sendable> {
    private var stored: Result<T, Error>?

    func set(_ result: Result<T, Error>) {
        stored = result
    }

    func value() throws -> T {
        guard let stored else {
            throw JjProcessQueueError.bodyDidNotRun
        }
        return try stored.get()
    }
}

enum JjProcessQueueError: Error, Sendable {
    case bodyDidNotRun
}
