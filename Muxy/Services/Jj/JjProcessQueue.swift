import Foundation

public actor JjProcessQueue {
    private var inflight: [String: Task<Void, Never>] = [:]

    public init() {}

    public func run(repoPath: String, isMutating: Bool, body: @Sendable @escaping () async -> Void) async {
        if !isMutating {
            await body()
            return
        }
        let previous = inflight[repoPath]
        let task = Task {
            await previous?.value
            await body()
        }
        inflight[repoPath] = task
        await task.value
        if inflight[repoPath] == task {
            inflight[repoPath] = nil
        }
    }
}
