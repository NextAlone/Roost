import Foundation

enum HostdAsyncTimeoutError: Error, LocalizedError, Equatable, Sendable {
    case timedOut(operation: String)

    var errorDescription: String? {
        switch self {
        case let .timedOut(operation):
            "Timed out waiting for hostd \(operation)"
        }
    }
}

enum HostdAsyncTimeout {
    static func run<T: Sendable>(
        seconds: TimeInterval,
        operation: String,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard seconds > 0 else { return try await work() }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = HostdTimeoutContinuation(continuation)
            let task = Task {
                do {
                    let value = try await work()
                    gate.resume(.success(value))
                } catch {
                    gate.resume(.failure(error))
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if gate.resume(.failure(HostdAsyncTimeoutError.timedOut(operation: operation))) {
                    task.cancel()
                }
            }
        }
    }
}

private final class HostdTimeoutContinuation<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    @discardableResult
    func resume(_ result: Result<T, Error>) -> Bool {
        let continuation = lock.withLock {
            let current = self.continuation
            self.continuation = nil
            return current
        }
        guard let continuation else { return false }
        continuation.resume(with: result)
        return true
    }
}
