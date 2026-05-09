import SwiftUI

struct AgentReloadBanner: View {
    let model: Model

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.iconName)
                .foregroundStyle(model.tint)
            Text(model.title)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button(model.primaryLabel, action: model.onPrimary)
                .buttonStyle(.borderedProminent)
                .disabled(!model.primaryButtonEnabled)
            Button(action: model.onDismiss) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(model.tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    struct Model {
        let title: String
        let iconName: String
        let tint: Color
        let primaryLabel: String
        let primaryButtonEnabled: Bool
        let onPrimary: () -> Void
        let onDismiss: () -> Void

        static func exit(
            agentName: String,
            captured: String?,
            onResume: @escaping () -> Void,
            onDismiss: @escaping () -> Void
        ) -> Model {
            Model(
                title: "\(agentName) exited.",
                iconName: "circle.fill",
                tint: .orange,
                primaryLabel: "Reload Agent",
                primaryButtonEnabled: captured != nil,
                onPrimary: onResume,
                onDismiss: onDismiss
            )
        }

        static func binaryUpdate(
            agentName: String,
            onReload: @escaping () -> Void,
            onDismiss: @escaping () -> Void
        ) -> Model {
            Model(
                title: "\(agentName) binary updated since launch.",
                iconName: "arrow.triangle.2.circlepath",
                tint: .blue,
                primaryLabel: "Reload",
                primaryButtonEnabled: true,
                onPrimary: onReload,
                onDismiss: onDismiss
            )
        }
    }
}
