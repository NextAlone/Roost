import Darwin
import Foundation

public enum HostdDaemonInstanceLockError: Error, LocalizedError, Equatable {
    case alreadyRunning(pid_t?)
    case openFailed(String)
    case removeStaleFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .alreadyRunning(pid):
            if let pid {
                "roost-hostd-daemon is already running with pid \(pid)"
            } else {
                "roost-hostd-daemon is already running"
            }
        case let .openFailed(message):
            "Failed to open hostd daemon lock: \(message)"
        case let .removeStaleFailed(message):
            "Failed to remove stale hostd daemon lock: \(message)"
        case let .writeFailed(message):
            "Failed to write hostd daemon lock: \(message)"
        }
    }
}

public final class HostdDaemonInstanceLock {
    private let url: URL
    private let fd: CInt

    public init(url: URL = HostdStorage.defaultDaemonLockURL()) throws {
        self.url = url
        try HostdStorage.ensureParentDirectory(for: url)
        fd = try Self.openLock(url)
        do {
            try Self.acquire(fd, url: url)
        } catch {
            close(fd)
            throw error
        }
    }

    deinit {
        flock(fd, LOCK_UN)
        close(fd)
    }

    private static func openLock(_ url: URL) throws -> CInt {
        while true {
            let fd = open(url.path(percentEncoded: false), O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
            if fd >= 0 { return fd }
            let code = errno
            guard code == EISDIR else {
                throw HostdDaemonInstanceLockError.openFailed(hostdLockErrnoMessage(code))
            }
            let pid = readDirectoryPID(from: url)
            guard pid.map(isProcessAlive) != true else {
                throw HostdDaemonInstanceLockError.alreadyRunning(pid)
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                throw HostdDaemonInstanceLockError.removeStaleFailed(error.localizedDescription)
            }
        }
    }

    private static func acquire(_ fd: CInt, url: URL) throws {
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            try writeCurrentPID(to: fd)
            return
        }
        let code = errno
        guard code == EWOULDBLOCK || code == EAGAIN else {
            throw HostdDaemonInstanceLockError.openFailed(hostdLockErrnoMessage(code))
        }
        throw HostdDaemonInstanceLockError.alreadyRunning(readPID(from: url))
    }

    private static func writeCurrentPID(to fd: CInt) throws {
        let data = Data("\(getpid())\n".utf8)
        guard ftruncate(fd, 0) == 0, lseek(fd, 0, SEEK_SET) >= 0 else {
            throw HostdDaemonInstanceLockError.writeFailed(hostdLockErrnoMessage())
        }
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return Darwin.write(fd, baseAddress.advanced(by: offset), data.count - offset)
            }
            if count > 0 {
                offset += count
                continue
            }
            if errno == EINTR { continue }
            throw HostdDaemonInstanceLockError.writeFailed(hostdLockErrnoMessage())
        }
    }

    private static func readPID(from url: URL) -> pid_t? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value > 0
        else { return nil }
        return pid_t(value)
    }

    private static func readDirectoryPID(from url: URL) -> pid_t? {
        readPID(from: url.appendingPathComponent("pid", isDirectory: false))
    }

    private static func isProcessAlive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}

private func hostdLockErrnoMessage(_ code: Int32 = errno) -> String {
    String(cString: strerror(code))
}
