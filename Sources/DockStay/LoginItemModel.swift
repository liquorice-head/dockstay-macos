import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemModel {
    private(set) var status = SMAppService.mainApp.status
    private(set) var errorMessage: String?

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        refresh()
        guard enabled != isEnabled else { return }
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = String(localized: "Could not change launch at login. Try again.")
        }
        // macOS owns the setting, including changes made outside DockStay.
        refresh()
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
