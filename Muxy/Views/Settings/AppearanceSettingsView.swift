import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
    @State private var themeService = ThemeService.shared
    @State private var showThemePicker = false
    @State private var currentTheme: String?
    @AppStorage(AppIconSettings.selectedIconKey) private var selectedIconRaw = AppIconSettings.defaultVariant.rawValue
    @AppStorage("muxy.vcsDisplayMode") private var vcsDisplayMode = VCSDisplayMode.attached.rawValue
    @AppStorage(SidebarCollapsedStyle.storageKey) private var sidebarCollapsedStyle = SidebarCollapsedStyle.defaultValue.rawValue
    @AppStorage(SidebarExpandedStyle.storageKey) private var sidebarExpandedStyle = SidebarExpandedStyle.defaultValue.rawValue

    private var selectedIcon: AppIconVariant {
        AppIconVariant.resolved(rawValue: selectedIconRaw)
    }

    var body: some View {
        SettingsContainer {
            SettingsSection("Application") {
                SettingsRow("App Icon") {
                    HStack(spacing: 8) {
                        ForEach(AppIconVariant.allCases) { variant in
                            AppIconButton(
                                variant: variant,
                                isSelected: selectedIcon == variant
                            ) {
                                selectedIconRaw = variant.rawValue
                                AppIconService.apply(variant)
                            }
                        }
                    }
                }
            }

            SettingsSection("Terminal") {
                SettingsRow("Theme") {
                    Button {
                        showThemePicker.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentTheme ?? "Default")
                                .font(.system(size: SettingsMetrics.labelFontSize))
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showThemePicker) {
                        ThemePicker()
                            .environment(themeService)
                    }
                }
            }

            SettingsSection("Sidebar") {
                SettingsRow("Collapsed Style") {
                    HStack {
                        Spacer()
                        Picker("", selection: $sidebarCollapsedStyle) {
                            ForEach(SidebarCollapsedStyle.allCases) { style in
                                Text(style.title).tag(style.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .frame(width: SettingsMetrics.controlWidth)
                }

                SettingsRow("Expanded Style") {
                    HStack {
                        Spacer()
                        Picker("", selection: $sidebarExpandedStyle) {
                            ForEach(SidebarExpandedStyle.allCases) { style in
                                Text(style.title).tag(style.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .frame(width: SettingsMetrics.controlWidth)
                }
            }

            SettingsSection("Source Control", showsDivider: false) {
                SettingsRow("Display Mode") {
                    Picker("", selection: $vcsDisplayMode) {
                        ForEach(VCSDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: SettingsMetrics.controlWidth)
                }
            }
        }
        .task {
            currentTheme = themeService.currentThemeName()
        }
        .onReceive(NotificationCenter.default.publisher(for: .themeDidChange)) { _ in
            currentTheme = themeService.currentThemeName()
        }
    }
}

private struct AppIconButton: View {
    let variant: AppIconVariant
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                iconImage
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(variant.displayName)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 58)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(width: 68, height: 64)
            .background(background)
            .overlay(border)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(variant.displayName)
    }

    @ViewBuilder
    private var iconImage: some View {
        if let image = AppIconService.image(for: variant) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.28), lineWidth: isSelected ? 1.4 : 1)
    }
}
