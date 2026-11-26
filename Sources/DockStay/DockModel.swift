import AppKit
@preconcurrency import ApplicationServices
import DockStayCore
import Observation

struct ScreenChoice: Identifiable, Equatable {
    let id: String
    let display: Display
    let name: String
}

@MainActor
@Observable
final class DockModel {
    private(set) var screens: [ScreenChoice] = []
    private(set) var selectedID: String?
    private(set) var remembersConfigurations: Bool
    private(set) var savedConfigurations: [SavedDisplayConfiguration]
    private(set) var isBlockingEnabled: Bool
    private(set) var isBlockingActive = false
    private(set) var status = String(localized: "Choose a display")
    private(set) var hasAccessibilityPermission = false

    @ObservationIgnored private let pointer = PointerGuard()
    @ObservationIgnored private let placement = DockPlacement()
    @ObservationIgnored private let displaySelections = DisplaySelections(defaults: .standard)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingPlacement = false
    @ObservationIgnored private var sleeping = false
    @ObservationIgnored private var placementRequest: Task<Void, Never>?

    init() {
        isBlockingEnabled = UserDefaults.standard.object(forKey: "blockingEnabled") as? Bool ?? true
        remembersConfigurations = displaySelections.remembersConfigurations
        savedConfigurations = displaySelections.configurations
        refreshScreens()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshScreens() }
        })
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleeping = true
                    self?.reconcile()
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.sleeping = false
                    self.pendingPlacement = self.isBlockingEnabled && self.selectedID != nil
                    self.refreshScreens()
                }
            })
        }
        timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        reconcile()
    }

    func select(_ id: String) {
        let displays = connectedDisplays
        guard displays[id] != nil else { return }
        applySelection(id)
        if remembersConfigurations {
            displaySelections.setSelectedID(id, for: displays)
            savedConfigurations = displaySelections.configurations
        }
        if isBlockingEnabled && !AXIsProcessTrusted() { openPermissionSettings() }
        reconcile()
    }

    func setRemembersConfigurations(_ enabled: Bool) {
        guard remembersConfigurations != enabled else { return }
        displaySelections.remembersConfigurations = enabled
        remembersConfigurations = enabled
        if enabled, let id = restoreSelection(for: connectedDisplays), id != selectedID {
            applySelection(id)
            reconcile()
        }
    }

    func removeConfiguration(_ id: String) {
        displaySelections.removeConfiguration(id)
        savedConfigurations = displaySelections.configurations
    }

    func setBlockingEnabled(_ enabled: Bool) {
        isBlockingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "blockingEnabled")
        pendingPlacement = enabled && selectedID != nil
        if pendingPlacement && !AXIsProcessTrusted() { openPermissionSettings() }
        reconcile()
    }

    func openPermissionSettings() {
        if !AXIsProcessTrusted() {
            // Register the app with TCC before opening the permission list.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        // Best-effort System Settings navigation; no permission is granted programmatically.
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        if !NSWorkspace.shared.open(url),
           let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: settings, configuration: .init())
        }
        reconcile()
    }

    private func suspendBlocking() {
        placementRequest?.cancel()
        placementRequest = nil
        placement.cancel()
        pointer.stop()
        isBlockingActive = false
    }

    private func applySelection(_ id: String) {
        placementRequest?.cancel()
        placement.cancel()
        selectedID = id
        pendingPlacement = isBlockingEnabled
    }

    private var connectedDisplays: [String: String] {
        Dictionary(screens.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private func restoreSelection(for displays: [String: String]) -> String? {
        let id = displaySelections.selectedID(for: displays)
        savedConfigurations = displaySelections.configurations
        return id
    }

    func stop() {
        timer?.invalidate()
        suspendBlocking()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        workspaceObservers.removeAll()
    }

    private func refreshScreens() {
        let updated = NSScreen.screens.compactMap { screen -> ScreenChoice? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else {
                return nil
            }
            let id = CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
            return ScreenChoice(id: id, display: Display(id: id, bounds: CGDisplayBounds(number.uint32Value)),
                                name: screen.localizedName)
        }.sorted {
            if $0.display.bounds.minX != $1.display.bounds.minX {
                return $0.display.bounds.minX < $1.display.bounds.minX
            }
            if $0.display.bounds.minY != $1.display.bounds.minY {
                return $0.display.bounds.minY < $1.display.bounds.minY
            }
            return $0.id < $1.id
        }
        if screens != updated {
            placementRequest?.cancel()
            placement.cancel()
            let previousIDs = Set(screens.map(\.id))
            screens = updated
            let displays = connectedDisplays
            if previousIDs != Set(displays.keys) {
                if remembersConfigurations {
                    selectedID = restoreSelection(for: displays)
                } else if let selectedID, displays[selectedID] == nil {
                    self.selectedID = nil
                }
            }
            pendingPlacement = isBlockingEnabled && selectedID != nil
        }
        reconcile()
    }

    private func reconcile() {
        // Keep permission information current even while blocking is switched off.
        hasAccessibilityPermission = AXIsProcessTrusted()
        guard isBlockingEnabled else {
            suspendBlocking()
            status = String(localized: "Blocking is off")
            return
        }
        guard !sleeping else {
            suspendBlocking()
            status = String(localized: "Blocking is paused")
            return
        }
        guard let selectedID, let selectedDisplay = screens.first(where: { $0.id == selectedID })?.display else {
            suspendBlocking()
            status = String(localized: "Choose a display")
            return
        }
        let edge = (CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String)
            .flatMap(DockEdge.init(rawValue:)) ?? .bottom
        if pointer.geometry.edge != edge { pendingPlacement = true }
        pointer.geometry = EdgeGuard(displays: screens.map(\.display), selectedID: selectedID, edge: edge)
        guard hasAccessibilityPermission else {
            suspendBlocking()
            status = String(localized: "Accessibility access required")
            return
        }
        guard NSScreen.screensHaveSeparateSpaces else {
            suspendBlocking()
            status = String(localized: "Enable separate Spaces for displays")
            return
        }
        guard pointer.geometry.activationPoint(for: selectedDisplay) != nil else {
            suspendBlocking()
            status = String(localized: "This display has no free Dock edge")
            return
        }
        isBlockingActive = pointer.start()
        guard isBlockingActive else {
            status = String(localized: "Could not start. Quit and reopen DockStay.")
            return
        }
        status = String(localized: "Blocking is active")
        if pendingPlacement {
            pendingPlacement = false
            // Let the native menu close before synthesizing the edge gesture.
            placementRequest?.cancel()
            placementRequest = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, !Task.isCancelled, self.isBlockingEnabled,
                      !self.sleeping, self.pointer.isRunning, AXIsProcessTrusted() else { return }
                if !self.placement.place(using: self.pointer.geometry) {
                    self.status = String(localized: "Move the pointer to this display’s Dock edge once")
                }
            }
        }
    }
}
