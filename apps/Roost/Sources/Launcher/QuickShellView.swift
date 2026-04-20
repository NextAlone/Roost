import SwiftUI

/// Shown when no project is selected. The app's whole feature surface
/// (agent picking, jj workspace management) needs a project to hang off, so
/// we degrade to a single "open a plain terminal in $HOME" action + a
/// prompt to add a project.
struct QuickShellView: View {
    let onOpenTerminal: () -> Void
    let onAddProject: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Add a project to manage agents and workspaces.")
                .font(.headline)
            Text("Or open a plain shell if you just want a scratch terminal.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(action: onAddProject) {
                    Label("Add project", systemImage: "folder.badge.plus")
                        .labelStyle(.titleAndIcon)
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onOpenTerminal) {
                    Label("Open terminal", systemImage: "terminal")
                        .labelStyle(.titleAndIcon)
                        .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
