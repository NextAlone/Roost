import SwiftUI
import GhosttyKit

struct ContentView: View {
    private let info = GhosttyInfo.current
    @State private var commandDraft: String = Self.defaultCommand
    @State private var launched: LaunchedSession?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
            Text("libghostty")
                .bold()
            Text("\(info.version) · \(info.buildMode)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let launched {
                Text(launched.command.isEmpty ? "(default shell)" : launched.command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Stop") {
                    self.launched = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if let launched {
            TerminalView(command: launched.command.isEmpty ? nil : launched.command)
                .id(launched.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            launcher
        }
    }

    private var launcher: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Command")
                .font(.headline)
            TextField("/path/to/agent", text: $commandDraft, onCommit: launch)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
            HStack {
                Text("Leave empty for user's login shell.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Launch") { launch() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func launch() {
        launched = LaunchedSession(
            command: commandDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static var defaultCommand: String {
        // Apps launched via Finder/Xcode inherit launchd's minimal PATH, so
        // prefer an absolute path or a shell wrapper. Fall back to a generic
        // hint if we can't guess.
        let candidates = [
            ("\(NSHomeDirectory())/.local/bin/claude"),
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/bin/zsh -il -c claude"
    }
}

private struct LaunchedSession: Identifiable {
    let id = UUID()
    let command: String
}

/// Thin wrapper around `ghostty_info()`.
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
