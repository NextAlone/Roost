import MuxyShared
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(TabCloseConfirmationPreferences.confirmRunningProcessKey)
    private var confirmRunningProcess = true
    @AppStorage(ProjectLifecyclePreferences.keepOpenWhenNoTabsKey)
    private var keepProjectsOpenWhenNoTabs = false
    @AppStorage(AgentToolbarSettings.visibleAgentsKey)
    private var visibleAgentsRaw = AgentToolbarSettings.defaultVisibleAgentsRaw

    var body: some View {
        SettingsContainer {
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

            SettingsSection("Tabs") {
                SettingsToggleRow(
                    label: "Confirm before closing a tab with a running process",
                    isOn: $confirmRunningProcess
                )
            }

            SettingsSection(
                "Tab Toolbar",
                footer: "Terminal is always shown. Choose which agent tab buttons appear beside it.",
                showsDivider: false
            ) {
                ForEach(AgentToolbarSettings.configurableAgentKinds, id: \.self) { kind in
                    SettingsToggleRow(
                        label: kind.displayName,
                        isOn: visibleBinding(for: kind)
                    )
                }
            }
        }
    }

    private func visibleBinding(for kind: AgentKind) -> Binding<Bool> {
        Binding {
            AgentToolbarSettings.isVisible(kind, in: visibleAgentsRaw)
        } set: { visible in
            visibleAgentsRaw = AgentToolbarSettings.setVisible(visible, for: kind, in: visibleAgentsRaw)
        }
    }
}
