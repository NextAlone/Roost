import SwiftUI
import GhosttyKit

struct ContentView: View {
    private let info = GhosttyInfo.current
    private let bridgeVersion = roost_bridge_version().toString()
    @State private var agentDraft: String = "claude"
    @State private var launched: LaunchedSession?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onReceive(NotificationCenter.default.publisher(for: .roostSurfaceClosed)) { _ in
            launched = nil
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
            Text("roost-bridge \(bridgeVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let launched {
                Text("· \(launched.spec.agentKind)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Button("Stop") { self.launched = nil }
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
            TerminalView(
                command: launched.spec.command.isEmpty ? nil : launched.spec.command,
                workingDirectory: launched.spec.workingDirectory.isEmpty
                    ? nil : launched.spec.workingDirectory
            )
            .id(launched.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            launcher
        }
    }

    private var launcher: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Agent")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(["claude", "codex", "shell"], id: \.self) { name in
                    Button(name) { agentDraft = name }
                        .buttonStyle(.bordered)
                        .tint(agentDraft == name ? .accentColor : .secondary)
                }
            }

            TextField("custom agent name", text: $agentDraft, onCommit: launch)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())

            HStack {
                Text("Rust resolves the binary path; falls back to 'zsh -il -c <agent>'.")
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
        let raw = roost_prepare_session(agentDraft)
        let spec = PreparedSpec(
            command: raw.command.toString(),
            workingDirectory: raw.working_directory.toString(),
            agentKind: raw.agent_kind.toString()
        )
        launched = LaunchedSession(spec: spec)
    }
}

private struct PreparedSpec {
    let command: String
    let workingDirectory: String
    let agentKind: String
}

private struct LaunchedSession: Identifiable {
    let id = UUID()
    let spec: PreparedSpec
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
