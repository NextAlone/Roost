import Darwin
import Foundation

public enum HostdSocketIOError: Error, LocalizedError, Equatable {
    case socketPathTooLong
    case socketFailed(String)
    case connectFailed(String)
    case messageTooLarge
    case readFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .socketPathTooLong:
            "Hostd socket path is too long"
        case let .socketFailed(message):
            "Hostd socket failed: \(message)"
        case let .connectFailed(message):
            "Hostd socket connect failed: \(message)"
        case .messageTooLarge:
            "Hostd socket message is too large"
        case let .readFailed(message):
            "Hostd socket read failed: \(message)"
        case let .writeFailed(message):
            "Hostd socket write failed: \(message)"
        }
    }
}

public enum HostdSocketIO {
    public static let maxSocketPathLength = 103
    public static let maxMessageSize = 16 * 1024 * 1024

    public static func connect(path: String) throws -> CInt {
        guard path.utf8.count <= maxSocketPathLength else {
            throw HostdSocketIOError.socketPathTooLong
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw HostdSocketIOError.socketFailed(errnoMessage())
        }
        try setCloseOnExec(fd)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let bound = ptr.withMemoryRebound(to: CChar.self, capacity: 104) { $0 }
            _ = path.withCString { strncpy(bound, $0, 103) }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let message = errnoMessage()
            close(fd)
            throw HostdSocketIOError.connectFailed(message)
        }
        return fd
    }

    public static func setCloseOnExec(_ fd: CInt) throws {
        let flags = fcntl(fd, F_GETFD)
        guard flags >= 0 else {
            throw HostdSocketIOError.socketFailed(errnoMessage())
        }
        guard fcntl(fd, F_SETFD, flags | FD_CLOEXEC) >= 0 else {
            throw HostdSocketIOError.socketFailed(errnoMessage())
        }
    }

    public static func readAll(from fd: CInt) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer[0 ..< count])
                if data.count > maxMessageSize {
                    throw HostdSocketIOError.messageTooLarge
                }
                continue
            }
            if count == 0 { return data }
            if errno == EINTR { continue }
            throw HostdSocketIOError.readFailed(errnoMessage())
        }
    }

    public static func writeAll(_ data: Data, to fd: CInt) throws {
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return write(fd, baseAddress.advanced(by: offset), data.count - offset)
            }
            if count > 0 {
                offset += count
                continue
            }
            if count == -1, errno == EINTR {
                continue
            }
            throw HostdSocketIOError.writeFailed(errnoMessage())
        }
    }

    private static func errnoMessage(_ code: Int32 = errno) -> String {
        String(cString: strerror(code))
    }
}
