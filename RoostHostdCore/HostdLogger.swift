import Darwin
import Foundation
import os

public enum HostdLogger {
    public static let detection = Logger(subsystem: "app.roost.hostd", category: "AgentDetection")

    private static let logFD: Int32 = {
        let path = "/tmp/roost-hostd-detection.log"
        let fd = open(path, O_CREAT | O_WRONLY | O_APPEND, 0o644)
        return fd >= 0 ? fd : -1
    }()

    public static func log(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        if let data = line.data(using: .utf8), logFD >= 0 {
            data.withUnsafeBytes { buf in
                _ = write(logFD, buf.baseAddress, buf.count)
            }
        }
    }
}
