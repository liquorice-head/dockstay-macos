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
    private(set) var selectedID: String
    private(set) var selectedName: String
    private(set) var isBlockingEnabled: Bool
    private(set) var isBlockingActive = false
    private(set) var status = String(localized: "Choose a display")
    private(set) var hasAccessibilityPermission = false

    @ObservationIgnored private let pointer = PointerGuard()
    @ObservationIgnored private let placement = DockPlacement()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingPlacement = false
    @ObservationIgnored private var sleeping = false
    @ObservationIgnored private var placementRequest: Task<Void, Never>?

    init() {
        selectedID = UserDefaults.standard.string(forKey: "selectedDisplayUUID") ?? ""
        selectedName = UserDefaults.standard.string(forKey: "selectedDisplayName") ?? ""
        isBlockingEnabled = UserDefaults.standard.object(forKey: "blockingEnabled") as? Bool ?? true
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
                    self?.sleeping = false
                    self?.pendingPlacement = true
                    self?.refreshScreens()
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
        guard let screen = screens.first(where: { $0.id == id }) else { return }
        placementRequest?.cancel()
        placement.cancel()
        selectedID = id
        selectedName = screen.name
        UserDefaults.standard.set(id, forKey: "selectedDisplayUUID")
        UserDefaults.standard.set(screen.name, forKey: "selectedDisplayName")
        pendingPlacement = isBlockingEnabled
        if isBlockingEnabled && !AXIsProcessTrusted() { openPermissionSettings() }
        reconcile()
    }

    func setBlockingEnabled(_ enabled: Bool) {
        isBlockingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "blockingEnabled")
        pendingPlacement = enabled && !selectedID.isEmpty
        if enabled && !selectedID.isEmpty && !AXIsProcessTrusted() { openPermissionSettings() }
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
            screens = updated
            pendingPlacement = !selectedID.isEmpty
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
        let edge = (CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String)
            .flatMap(DockEdge.init(rawValue:)) ?? .bottom
        if pointer.geometry.edge != edge { pendingPlacement = !selectedID.isEmpty }
        pointer.geometry = EdgeGuard(displays: screens.map(\.display), selectedID: selectedID, edge: edge)
        guard !selectedID.isEmpty else {
            suspendBlocking()
            status = String(localized: "Choose a display")
            return
        }
        guard screens.contains(where: { $0.id == selectedID }) else {
            suspendBlocking()
            status = String(localized: "Waiting for selected display")
            return
        }
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
        guard let screen = pointer.geometry.displays.first(where: { $0.id == selectedID }),
              pointer.geometry.activationPoint(for: screen) != nil else {
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
