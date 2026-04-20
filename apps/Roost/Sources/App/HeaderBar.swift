import SwiftUI

struct HeaderBar: View {
    let ghosttyInfo: (version: String, buildMode: String)
    let bridgeVersion: String
    let launchedKind: String?
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
            Text("Roost")
                .bold()
            Text("ghostty \(ghosttyInfo.version) · \(ghosttyInfo.buildMode)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("bridge \(bridgeVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let kind = launchedKind {
                Text("· \(kind)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Button("Stop", action: onStop)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
