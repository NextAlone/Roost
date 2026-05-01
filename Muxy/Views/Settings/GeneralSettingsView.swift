import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(TabCloseConfirmationPreferences.confirmRunningProcessKey)
    private var confirmRunningProcess = true
    @AppStorage(ProjectLifecyclePreferences.keepOpenWhenNoTabsKey)
    private var keepProjectsOpenWhenNoTabs = false

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

            SettingsSection("Tabs", showsDivider: false) {
                SettingsToggleRow(
                    label: "Confirm before closing a tab with a running process",
                    isOn: $confirmRunningProcess
                )
            }
        }
    }
}
