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
                set: { model.select($0) }
            )) {
                if model.selectedID.isEmpty {
                    Text("Choose a display").tag("").disabled(true)
                }
                if !model.selectedID.isEmpty && !model.screens.contains(where: { $0.id == model.selectedID }) {
                    Text(model.selectedName).tag(model.selectedID).disabled(true)
                }
                ForEach(Array(model.screens.enumerated()), id: \.element.id) { index, screen in
                    Text("Display \(index + 1) — \(screen.name)").tag(screen.id)
                }
            }
            .pickerStyle(.inline)

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

    @ViewBuilder
    private func statusIndicator(isPositive: Bool) -> some View {
        if let image = NSImage(named: isPositive ? NSImage.statusAvailableName : NSImage.statusUnavailableName) {
            Image(nsImage: image).renderingMode(.original)
        }
    }
}
