import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            EditorSettingsView()
                .tabItem { Label("Editor", systemImage: "pencil.line") }
            KeyboardShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
            RoostConfigSettingsView()
                .tabItem { Label("Project Config", systemImage: "doc.badge.gearshape") }
            MobileSettingsView()
                .tabItem { Label("Mobile", systemImage: "iphone") }
            AIUsageSettingsView()
                .tabItem { Label("AI Usage", systemImage: "chart.bar") }
        }
        .frame(width: 820, height: 540)
        .resetsSettingsFocusOnOutsideClick()
    }
}
