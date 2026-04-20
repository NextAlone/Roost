import SwiftUI
import GhosttyKit

struct ContentView: View {
    private let info = GhosttyInfo.current

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TerminalView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "terminal")
            Text("libghostty")
                .bold()
            Text("\(info.version) · \(info.buildMode)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
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

#Preview {
    ContentView()
}
