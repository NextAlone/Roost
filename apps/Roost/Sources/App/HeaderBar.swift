import SwiftUI

struct HeaderBar: View {
    let ghosttyInfo: (version: String, buildMode: String)
    let bridgeVersion: String
    let sessionCount: Int

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
            if sessionCount > 0 {
                Text("· \(sessionCount) session\(sessionCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
