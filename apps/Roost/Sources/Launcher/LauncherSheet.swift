import SwiftUI

/// Sheet variant used when a session already exists. Wraps `LauncherView` with
/// a title bar + Cancel button.
struct LauncherSheet: View {
    @Binding var agentDraft: String
    let onLaunch: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New session").font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            LauncherView(agentDraft: $agentDraft, onLaunch: onLaunch)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 440, height: 320)
    }
}
