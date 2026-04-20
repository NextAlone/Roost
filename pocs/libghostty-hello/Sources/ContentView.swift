import SwiftUI
import GhosttyKit

struct ContentView: View {
    private let info = GhosttyInfo.current

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("libghostty linked")
                .font(.title2)
                .bold()
            VStack(alignment: .leading, spacing: 4) {
                Row(label: "Version", value: info.version)
                Row(label: "Build mode", value: info.buildMode)
            }
            .padding()
            .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(32)
    }
}

private struct Row: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
        }
    }
}

/// Thin wrapper around `ghostty_info()` so the SwiftUI layer doesn't handle
/// raw C types directly.
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
        default: buildMode = "Unknown(\(raw.build_mode.rawValue))"
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

#Preview {
    ContentView()
}
