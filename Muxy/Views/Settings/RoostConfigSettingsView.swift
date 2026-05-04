import AppKit
import MuxyShared
import SwiftUI

struct RoostConfigSettingsView: View {
    @Environment(ProjectStore.self) private var projectStore
    @State private var selectedProjectID: UUID?
    @State private var notificationsEnabled = true
    @State private var toastEnabled = true
    @State private var sound = NotificationSound.funk.rawValue
    @State private var toastPosition = ToastPosition.topCenter.rawValue
    @State private var statusMessage: String?
    @State private var fileSecurity: RoostConfigFileSecurity = .missing

    private var selectedProject: Project? {
        guard let selectedProjectID else { return projectStore.projects.first }
        return projectStore.projects.first { $0.id == selectedProjectID } ?? projectStore.projects.first
    }

    var body: some View {
        SettingsContainer {
            SettingsSection("Project") {
                SettingsRow("Repository") {
                    Picker("", selection: selectedProjectBinding) {
                        ForEach(projectStore.projects) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsMetrics.controlWidth, alignment: .trailing)
                    .disabled(projectStore.projects.isEmpty)
                }

                SettingsRow("Config File") {
                    HStack(spacing: 8) {
                        Text(fileSecurityText)
                            .font(.system(size: SettingsMetrics.footnoteFontSize))
                            .foregroundStyle(fileSecurityColor)
                        Button("Open") { openConfig() }
                            .disabled(selectedProject == nil)
                        Button("Fix") { fixPermissions() }
                            .disabled(!canFixPermissions)
                    }
                }
            }

            SettingsSection("Notifications") {
                SettingsToggleRow(label: "Enabled", isOn: $notificationsEnabled)
                SettingsToggleRow(label: "Toast", isOn: $toastEnabled)
                SettingsPickerRow<NotificationSound>(label: "Sound", selection: $sound, width: 160)
                SettingsPickerRow<ToastPosition>(label: "Position", selection: $toastPosition, width: 160)
            }

            SettingsSection("Actions", footer: statusMessage, showsDivider: false) {
                HStack {
                    Button("Reload") { loadAll() }
                    Button("Save Project") { saveProjectSettings() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedProject == nil)
                    Spacer()
                }
                .padding(.horizontal, SettingsMetrics.horizontalPadding)
                .padding(.vertical, SettingsMetrics.rowVerticalPadding)
            }
        }
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = projectStore.projects.first?.id
            }
            loadAll()
        }
        .onChange(of: selectedProjectID) { _, _ in
            loadSelectedProject()
        }
    }

    private var selectedProjectBinding: Binding<UUID?> {
        Binding(
            get: { selectedProject?.id },
            set: { selectedProjectID = $0 }
        )
    }

    private var fileSecurityText: String {
        switch fileSecurity {
        case .missing: "Missing"
        case .secure: "0600"
        case let .tooPermissive(permissions): String(format: "%03o", permissions)
        case .unknown: "Unknown"
        }
    }

    private var fileSecurityColor: Color {
        switch fileSecurity {
        case .secure: .secondary
        case .missing: .secondary
        case .tooPermissive: .orange
        case .unknown: .red
        }
    }

    private var canFixPermissions: Bool {
        if case .tooPermissive = fileSecurity { return true }
        return false
    }

    private func loadAll() {
        loadSelectedProject()
    }

    private func loadSelectedProject() {
        guard let project = selectedProject else {
            resetProjectFields()
            statusMessage = nil
            fileSecurity = .missing
            return
        }

        fileSecurity = RoostConfigStore.fileSecurity(projectPath: project.path)
        let config = try? RoostConfigStore.load(projectPath: project.path)
        let notifications = config?.notifications
        notificationsEnabled = notifications?.enabled ?? true
        toastEnabled = notifications?.toastEnabled ?? true
        sound = notifications?.sound.flatMap { NotificationSound(rawValue: $0)?.rawValue } ?? NotificationSound.funk.rawValue
        toastPosition = notifications?.toastPosition.flatMap { ToastPosition(rawValue: $0)?.rawValue } ?? ToastPosition.topCenter.rawValue
        statusMessage = nil
    }

    private func saveProjectSettings() {
        guard selectedProject != nil else { return }
        guard saveProjectConfig() else { return }
        statusMessage = "Saved project config."
    }

    @discardableResult
    private func saveProjectConfig() -> Bool {
        guard let project = selectedProject else { return true }
        let existing = try? RoostConfigStore.load(projectPath: project.path)
        let config = RoostConfig(
            schemaVersion: existing?.schemaVersion ?? 1,
            env: existing?.env ?? [:],
            keychainEnv: existing?.keychainEnv ?? [:],
            setup: existing?.setup ?? [],
            teardown: existing?.teardown ?? [],
            notifications: RoostConfigNotifications(
                enabled: notificationsEnabled,
                toastEnabled: toastEnabled,
                sound: sound,
                toastPosition: toastPosition
            )
        )

        do {
            try RoostConfigStore.save(config, projectPath: project.path)
            fileSecurity = RoostConfigStore.fileSecurity(projectPath: project.path)
            return true
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    private func fixPermissions() {
        guard let project = selectedProject else { return }
        do {
            try RoostConfigStore.enforceSecurePermissions(projectPath: project.path)
            fileSecurity = RoostConfigStore.fileSecurity(projectPath: project.path)
            statusMessage = "Permissions fixed."
        } catch {
            statusMessage = "Permission fix failed: \(error.localizedDescription)"
        }
    }

    private func openConfig() {
        guard let project = selectedProject else { return }
        let url = RoostConfigStore.configURL(projectPath: project.path)
        if !FileManager.default.fileExists(atPath: url.path) {
            saveProjectConfig()
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusMessage = "Open failed: config file was not created."
            return
        }
        if NSWorkspace.shared.open(url) {
            statusMessage = "Opened \(url.path)"
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            statusMessage = "Revealed \(url.path)"
        }
    }

    private func resetProjectFields() {
        notificationsEnabled = true
        toastEnabled = true
        sound = NotificationSound.funk.rawValue
        toastPosition = ToastPosition.topCenter.rawValue
    }
}
