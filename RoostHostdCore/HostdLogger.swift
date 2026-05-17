import Foundation
import os

public enum HostdLogger {
    public static let detection = Logger(subsystem: "app.roost.hostd", category: "AgentDetection")

    public static func log(_ msg: String) {
        #if DEBUG || DEV_MODE
        detection.debug("\(msg, privacy: .public)")
        #endif
    }
}
