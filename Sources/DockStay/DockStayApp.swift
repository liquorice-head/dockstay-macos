import DockStayCore
import SwiftUI

@main
struct DockStayApp: App {
    @State private var model = DockModel()
    @State private var loginItem = LoginItemModel()
    @StateObject private var updates = UpdateModel()

    var body: some Scene {
        MenuBarExtra("DockStay", systemImage: "dock.rectangle") {
            Toggle("Lock Dock", isOn: Binding(
                get: { model.isBlockingEnabled },
                set: { model.setBlockingEnabled($0) }
            ))
            Label {
                Text(model.status)
            } icon: {
                statusIndicator(isPositive: model.isBlockingActive)
            }
            Divider()

            Picker("Dock on", selection: Binding(
                get: { model.selectedID },
                set: { if let id = $0 { model.select(id) } }
            )) {
                if model.selectedID == nil {
                    Text("Choose a display").tag(nil as String?).disabled(true)
                }
                ForEach(Array(model.screens.enumerated()), id: \.element.id) { index, screen in
                    Text("Display \(index + 1) — \(screen.name)").tag(Optional(screen.id))
                }
            }
            .pickerStyle(.inline)
            savedConfigurationsMenu

            Divider()
            Button(action: model.openPermissionSettings) {
                Label {
                    if model.hasAccessibilityPermission {
                        Text("Accessibility: Allowed…")
                    } else {
                        Text("Accessibility: Not allowed…")
                    }
                } icon: {
                    statusIndicator(isPositive: model.hasAccessibilityPermission)
                }
            }
            .help("Open Accessibility settings")

            Divider()
            Toggle("Launch at Login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            .onAppear { loginItem.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
                loginItem.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                loginItem.refresh()
            }
            if loginItem.requiresApproval {
                Button("Allow Launch at Login…", action: loginItem.openSettings)
            }
            if let errorMessage = loginItem.errorMessage {
                Text(errorMessage)
            }
            Button("Check for Updates…", action: updates.checkForUpdates)
                .disabled(!updates.canCheckForUpdates)
                .help(updates.isConfigured
                      ? String(localized: "Check for a new version of DockStay")
                      : String(localized: "Updates are unavailable in this build"))
            Button("Quit DockStay") {
                model.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }

    private var savedConfigurationsMenu: some View {
        let configurations = model.savedConfigurations
        let titles = Dictionary(grouping: configurations) { configurationTitle($0) }

        return Menu("Saved Configurations") {
            Toggle("Remember Configurations", isOn: Binding(
                get: { model.remembersConfigurations },
                set: { model.setRemembersConfigurations($0) }
            ))
            Divider()
            if configurations.isEmpty {
                Text("No Saved Configurations")
            }
            ForEach(configurations) { configuration in
                let title = configurationTitle(configuration)
                let repeatedTitle = (titles[title]?.count ?? 0) > 1
                let dockName = displayName(configuration.selectedID, in: configuration)
                let repeatedName = configuration.displayIDs.filter { displayName($0, in: configuration) == dockName }.count > 1
                let dockDisplay = displayName(configuration.selectedID, in: configuration, includeID: repeatedName)
                Menu {
                    Text("Dock on: \(dockDisplay)")
                    Button("Delete Configuration", role: .destructive) {
                        model.removeConfiguration(configuration.id)
                    }
                } label: {
                    Text(verbatim: repeatedTitle ? configurationTitle(configuration, includeIDs: true) : title)
                }
            }
        }
    }

    private func configurationTitle(_ configuration: SavedDisplayConfiguration, includeIDs: Bool = false) -> String {
        configuration.displayIDs.map { displayName($0, in: configuration, includeID: includeIDs) }
            .sorted().joined(separator: " + ")
    }

    private func displayName(_ id: String, in configuration: SavedDisplayConfiguration, includeID: Bool = false) -> String {
        let suffix = String(id.suffix(8))
        guard let name = configuration.displayNames[id] else { return String(localized: "Display \(suffix)") }
        return includeID ? "\(name) (\(suffix))" : name
    }

    @ViewBuilder
    private func statusIndicator(isPositive: Bool) -> some View {
        if let image = NSImage(named: isPositive ? NSImage.statusAvailableName : NSImage.statusUnavailableName) {
            Image(nsImage: image).renderingMode(.original)
        }
    }
}
