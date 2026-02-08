import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            projectsTab
                .tabItem {
                    Label("Projects", systemImage: "folder")
                }
            notificationsTab
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
            dataTab
                .tabItem {
                    Label("Data", systemImage: "externaldrive")
                }
        }
        .frame(width: 480, height: 360)
    }

    // MARK: - General Tab

    @MainActor
    private var generalTab: some View {
        @Bindable var state = appState
        return Form {
            Toggle("Launch at Login", isOn: $state.settings.launchAtLogin)
                .onChange(of: appState.settings.launchAtLogin) { _, newValue in
                    updateLaunchAtLogin(newValue)
                    appState.saveSettings()
                }

            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                LabeledContent("Build", value: "1")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Projects Tab

    @MainActor
    private var projectsTab: some View {
        Form {
            Section("Scan Roots") {
                if appState.projectConfig.scanRoots.isEmpty {
                    Text("No scan roots configured.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(appState.projectConfig.scanRoots, id: \.self) { root in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            Text(root.path(percentEncoded: false))
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                            Button {
                                removeScanRoot(root)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button("Add Scan Root...") {
                    addScanRoot()
                }
            }

            Section("Manual Projects") {
                if appState.projectConfig.manualProjects.isEmpty {
                    Text("No manual projects added.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(appState.projectConfig.manualProjects, id: \.rootPath) { entry in
                        HStack {
                            Image(systemName: "folder.badge.person.crop")
                                .foregroundStyle(.secondary)
                            Text(entry.rootPath.path(percentEncoded: false))
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                        }
                    }
                }

                Button("Add Project...") {
                    addManualProject()
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Notifications Tab

    @MainActor
    private var notificationsTab: some View {
        @Bindable var state = appState
        return Form {
            Toggle("Enable Notifications", isOn: $state.settings.notificationsEnabled)
                .onChange(of: appState.settings.notificationsEnabled) { _, _ in
                    appState.saveSettings()
                }

            Section("Notification Types") {
                Toggle("Epic Milestones (25/50/75/100%)", isOn: $state.settings.notifyOnMilestones)
                    .onChange(of: appState.settings.notifyOnMilestones) { _, _ in
                        appState.saveSettings()
                    }
                Toggle("Task Status Changes", isOn: $state.settings.notifyOnTaskChanges)
                    .onChange(of: appState.settings.notifyOnTaskChanges) { _, _ in
                        appState.saveSettings()
                    }
                Toggle("New PRD Detected", isOn: $state.settings.notifyOnNewPRD)
                    .onChange(of: appState.settings.notifyOnNewPRD) { _, _ in
                        appState.saveSettings()
                    }
                Toggle("Progress Inconsistency", isOn: $state.settings.notifyOnInconsistency)
                    .onChange(of: appState.settings.notifyOnInconsistency) { _, _ in
                        appState.saveSettings()
                    }
            }
            .disabled(!appState.settings.notificationsEnabled)

            Section("Quiet Hours") {
                Toggle("Enable Quiet Hours", isOn: $state.settings.quietHoursEnabled)
                    .onChange(of: appState.settings.quietHoursEnabled) { _, _ in
                        appState.saveSettings()
                    }

                if appState.settings.quietHoursEnabled {
                    Stepper(
                        "Start: \(formatHour(appState.settings.quietHoursStart))",
                        value: $state.settings.quietHoursStart,
                        in: 0...23
                    )
                    .onChange(of: appState.settings.quietHoursStart) { _, _ in
                        appState.saveSettings()
                    }

                    Stepper(
                        "End: \(formatHour(appState.settings.quietHoursEnd))",
                        value: $state.settings.quietHoursEnd,
                        in: 0...23
                    )
                    .onChange(of: appState.settings.quietHoursEnd) { _, _ in
                        appState.saveSettings()
                    }
                }
            }
            .disabled(!appState.settings.notificationsEnabled)
        }
        .formStyle(.grouped)
    }

    // MARK: - Data Tab

    @MainActor
    private var dataTab: some View {
        @Bindable var state = appState
        return Form {
            Section("History") {
                Stepper(
                    "Retention: \(appState.settings.historyRetentionDays) days",
                    value: $state.settings.historyRetentionDays,
                    in: 7...365,
                    step: 7
                )
                .onChange(of: appState.settings.historyRetentionDays) { _, _ in
                    appState.saveSettings()
                }
            }

            Section("Export") {
                Button("Export Activity as JSON...") {
                    exportJSON()
                }
                Button("Export Activity as CSV...") {
                    exportCSV()
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func formatHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    private func addScanRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory to scan for projects"

        if panel.runModal() == .OK, let url = panel.url {
            appState.addScanRoot(url)
            appState.rescanAll()
        }
    }

    private func removeScanRoot(_ root: URL) {
        ProjectStore.removeScanRoot(root, from: &appState.projectConfig)
        appState.saveProjectConfig()
        appState.rescanAll()
    }

    private func addManualProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory"

        if panel.runModal() == .OK, let url = panel.url {
            appState.addManualProject(url)
            appState.rescanAll()
        }
    }

    // MARK: - Export

    private func exportJSON() {
        guard let store = appState.activityStore else { return }
        let events = store.events

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(events) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "piq-activity.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func exportCSV() {
        guard let store = appState.activityStore else { return }
        let events = store.events

        let formatter = ISO8601DateFormatter()
        var csv = "timestamp,item_type,item_name,old_status,new_status,file_path\n"
        for event in events {
            let ts = formatter.string(from: event.timestamp)
            let oldStatus = event.oldStatus?.rawValue ?? ""
            let filePath = event.filePath.path(percentEncoded: false)
            csv += "\(ts),\(event.itemType.rawValue),\"\(event.itemName)\",\(oldStatus),\(event.newStatus.rawValue),\"\(filePath)\"\n"
        }

        guard let data = csv.data(using: .utf8) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "piq-activity.csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: .atomic)
        }
    }
}
