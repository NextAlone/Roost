import AppKit
import MuxyShared
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(GeneralSettingsKeys.autoExpandWorktreesOnProjectSwitch)
    private var autoExpandWorktrees = false
    @AppStorage(GeneralSettingsKeys.defaultWorktreeParentPath)
    private var defaultWorktreeParentPath = ""
    @AppStorage(GeneralSettingsKeys.hostdRuntime)
    private var hostdRuntimeRaw = RoostConfigHostdRuntime.metadataOnly.rawValue
    @AppStorage(TabCloseConfirmationPreferences.confirmRunningProcessKey)
    private var confirmRunningProcess = true
    @AppStorage(AgentToolbarSettings.visibleAgentsKey)
    private var visibleAgentsRaw = AgentToolbarSettings.defaultVisibleAgentsRaw
    @AppStorage(ProjectLifecyclePreferences.keepOpenWhenNoTabsKey)
    private var keepProjectsOpenWhenNoTabs = false
    @AppStorage(QuitConfirmationPreferences.confirmQuitKey)
    private var confirmQuit = true

    var body: some View {
        SettingsContainer {
            SettingsSection(
                "Sidebar",
                footer: "Automatically reveal workspaces when you switch to a project."
            ) {
                SettingsToggleRow(
                    label: "Auto-expand workspaces on project switch",
                    isOn: $autoExpandWorktrees
                )
            }

            SettingsSection(
                "Projects",
                footer: "Keep projects in the sidebar after closing their last tab. "
                    + "To remove a project afterward, use the right-click menu."
            ) {
                SettingsToggleRow(
                    label: "Keep projects open after closing the last tab",
                    isOn: $keepProjectsOpenWhenNoTabs
                )
            }

            SettingsSection(
                "Workspaces",
                footer: "Roost creates a project-named subfolder inside this folder. "
                    + "Projects can still override this from the new workspace dialog."
            ) {
                worktreeLocationControl
            }

            SettingsSection(
                "Roost",
                footer: "Changing Hostd Runtime takes effect after restarting Roost."
            ) {
                SettingsRow("Hostd Runtime") {
                    Picker("", selection: $hostdRuntimeRaw) {
                        ForEach(RoostConfigHostdRuntime.allCases) { option in
                            Text(option.settingsTitle).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsMetrics.controlWidth, alignment: .trailing)
                }
            }

            SettingsSection("Tabs") {
                SettingsToggleRow(
                    label: "Confirm before closing a tab with a running process",
                    isOn: $confirmRunningProcess
                )
            }

            SettingsSection(
                "Tab Toolbar",
                footer: "Terminal is always shown. Choose which agent tab buttons appear beside it."
            ) {
                ForEach(AgentToolbarSettings.configurableAgentKinds, id: \.self) { kind in
                    SettingsToggleRow(
                        label: kind.displayName,
                        isOn: visibleBinding(for: kind)
                    )
                }
            }

            SettingsSection("Quit", showsDivider: false) {
                SettingsToggleRow(
                    label: "Confirm before quitting Roost",
                    isOn: $confirmQuit
                )
            }
        }
    }

    private var defaultWorktreeLocationText: String {
        defaultWorktreeParentPath.isEmpty ? "Roost App Support" : defaultWorktreeParentPath
    }

    private var worktreeLocationControl: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Default path for new workspaces")
                .font(.system(size: SettingsMetrics.labelFontSize))

            HStack(alignment: .center, spacing: 8) {
                pathDisplay
                    .layoutPriority(1)

                Button("Choose Folder...") {
                    chooseDefaultWorktreeParentPath()
                }
                .fixedSize(horizontal: true, vertical: false)

                Button("Use App Default") {
                    defaultWorktreeParentPath = ""
                }
                .fixedSize(horizontal: true, vertical: false)
                .disabled(defaultWorktreeParentPath.isEmpty)
            }
        }
        .padding(.horizontal, SettingsMetrics.horizontalPadding)
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
    }

    private var pathDisplay: some View {
        HStack(spacing: 7) {
            Image(systemName: defaultWorktreeParentPath.isEmpty ? "internaldrive" : "folder")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 15)

            Text(defaultWorktreeLocationText)
                .font(.system(size: SettingsMetrics.footnoteFontSize, design: .monospaced))
                .foregroundStyle(defaultWorktreeParentPath.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
        .frame(height: 22)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.quaternary.opacity(0.7), lineWidth: 1)
        )
    }

    private func chooseDefaultWorktreeParentPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the default folder for new workspaces"
        if let path = WorktreeLocationResolver.normalizedPath(defaultWorktreeParentPath) {
            panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaultWorktreeParentPath = url.path
    }

    private func visibleBinding(for kind: AgentKind) -> Binding<Bool> {
        Binding {
            AgentToolbarSettings.isVisible(kind, in: visibleAgentsRaw)
        } set: { visible in
            visibleAgentsRaw = AgentToolbarSettings.setVisible(visible, for: kind, in: visibleAgentsRaw)
        }
    }
}

private extension RoostConfigHostdRuntime {
    var settingsTitle: String {
        switch self {
        case .metadataOnly: "Metadata Only"
        case .hostdOwnedProcess: "Hostd Owned Process"
        }
    }
}
