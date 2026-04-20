import SwiftUI

/// Sheet variant used when a session already exists. Wraps `LauncherView`
/// with a title bar + Cancel button.
struct LauncherSheet: View {
    @Binding var form: LauncherForm
    @Binding var errorMessage: String?
    let projectSupportsWorkspaces: Bool
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

            LauncherView(
                form: $form,
                projectSupportsWorkspaces: projectSupportsWorkspaces,
                onLaunch: onLaunch
            )
            .frame(maxHeight: .infinity)
        }
        .frame(width: 480, height: 420)
        .alert(
            "Launch failed",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            presenting: errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }
}
