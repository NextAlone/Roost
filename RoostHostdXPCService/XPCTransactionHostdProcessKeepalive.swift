import Foundation
import RoostHostdCore
import XPC

final class XPCTransactionHostdProcessKeepalive: HostdProcessKeepalive, @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0

    deinit {
        lock.withLock {
            while activeCount > 0 {
                activeCount -= 1
                xpc_transaction_end()
            }
        }
    }

    func retainSession() {
        lock.withLock {
            if activeCount == 0 {
                xpc_transaction_begin()
            }
            activeCount += 1
        }
    }

    func releaseSession() {
        lock.withLock {
            guard activeCount > 0 else { return }
            activeCount -= 1
            if activeCount == 0 {
                xpc_transaction_end()
            }
        }
    }
}
