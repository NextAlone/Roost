import Darwin
import Foundation

struct HostdAttachTerminalSize: Equatable {
    let columns: UInt16
    let rows: UInt16
}

enum HostdAttachTerminalError: Error, LocalizedError {
    case rawModeFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case let .rawModeFailed(message):
            "Unable to configure terminal raw mode: \(message)"
        case let .writeFailed(message):
            "Unable to write terminal output: \(message)"
        }
    }
}

struct HostdAttachTerminal {
    private let inputFD: CInt
    private let outputFD: CInt
    private var originalTermios = termios()
    private var rawModeEnabled = false

    static func standard() -> HostdAttachTerminal {
        HostdAttachTerminal(inputFD: STDIN_FILENO, outputFD: STDOUT_FILENO)
    }

    init(inputFD: CInt, outputFD: CInt) {
        self.inputFD = inputFD
        self.outputFD = outputFD
    }

    mutating func enableRawMode() throws {
        guard isatty(inputFD) != 0 else { return }
        guard tcgetattr(inputFD, &originalTermios) == 0 else {
            throw HostdAttachTerminalError.rawModeFailed(errnoMessage())
        }
        var raw = originalTermios
        cfmakeraw(&raw)
        guard tcsetattr(inputFD, TCSANOW, &raw) == 0 else {
            throw HostdAttachTerminalError.rawModeFailed(errnoMessage())
        }
        rawModeEnabled = true
    }

    mutating func restore() {
        guard rawModeEnabled else { return }
        tcsetattr(inputFD, TCSANOW, &originalTermios)
        rawModeEnabled = false
    }

    func size() -> HostdAttachTerminalSize? {
        var windowSize = winsize()
        guard ioctl(outputFD, TIOCGWINSZ, &windowSize) == 0 else { return nil }
        guard windowSize.ws_col > 0, windowSize.ws_row > 0 else { return nil }
        return HostdAttachTerminalSize(columns: windowSize.ws_col, rows: windowSize.ws_row)
    }

    static func writeAll(_ data: Data, to fd: CInt = STDOUT_FILENO) throws {
        guard !data.isEmpty else { return }
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
            if count == -1 {
                let code = errno
                if code == EINTR || code == EAGAIN || code == EWOULDBLOCK {
                    continue
                }
            }
            throw HostdAttachTerminalError.writeFailed(errnoMessage())
        }
    }
}

func errnoMessage(_ code: Int32 = errno) -> String {
    String(cString: strerror(code))
}
