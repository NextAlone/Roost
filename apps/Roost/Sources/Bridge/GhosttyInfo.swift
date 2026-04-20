import Foundation
import GhosttyKit

/// Swift-friendly read of `ghostty_info()`.
enum GhosttyInfo {
    static var current: (version: String, buildMode: String) {
        let raw = ghostty_info()
        let version = readCString(ptr: raw.version, length: Int(raw.version_len))
        let buildMode: String
        switch raw.build_mode {
        case GHOSTTY_BUILD_MODE_DEBUG: buildMode = "Debug"
        case GHOSTTY_BUILD_MODE_RELEASE_SAFE: buildMode = "ReleaseSafe"
        case GHOSTTY_BUILD_MODE_RELEASE_FAST: buildMode = "ReleaseFast"
        case GHOSTTY_BUILD_MODE_RELEASE_SMALL: buildMode = "ReleaseSmall"
        default: buildMode = "Unknown"
        }
        return (version, buildMode)
    }

    private static func readCString(ptr: UnsafePointer<CChar>?, length: Int) -> String {
        guard let ptr, length > 0 else { return "unknown" }
        return (NSString(
            bytes: ptr,
            length: length,
            encoding: String.Encoding.utf8.rawValue
        ) as String?) ?? "unknown"
    }
}
