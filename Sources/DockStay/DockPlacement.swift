import AppKit
import ApplicationServices
import DockStayCore

/// macOS has no public Dock-placement API. Replay the normal edge gesture once on selection.
@MainActor
final class DockPlacement {
    private var task: Task<Void, Never>?
    private var lastPosted: CGPoint?
    private var original: CGPoint?
    private var mouseHidden = false
    private var generation = 0
    private let eventTag: Int64 = 0x444F434B53544159

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        restorePointer()
    }

    func place(using geometry: EdgeGuard) -> Bool {
        cancel()
        guard let display = geometry.displays.first(where: { $0.id == geometry.selectedID }),
              let target = geometry.activationPoint(for: display),
              CGEventSource.buttonState(.combinedSessionState, button: .left) == false,
              CGEventSource.buttonState(.combinedSessionState, button: .right) == false,
              let source = CGEventSource(stateID: .privateState),
              let cursor = CGEvent(source: nil)?.location else { return false }

        original = cursor
        let attempt = generation
        NSCursor.hide()
        mouseHidden = true
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generation == attempt {
                    self.restorePointer()
                    self.task = nil
                }
            }
            var approach = target
            switch geometry.edge {
            case .bottom: approach.y -= 16
            case .left: approach.x += 16
            case .right: approach.x -= 16
            }
            self.post(at: approach, edge: geometry.edge, source: source)
            // Stop immediately if the user moves or clicks; never fight their pointer.
            for _ in 0..<20 {
                do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
                guard !Task.isCancelled,
                      !CGEventSource.buttonState(.combinedSessionState, button: .left),
                      !CGEventSource.buttonState(.combinedSessionState, button: .right),
                      let current = CGEvent(source: nil)?.location,
                      let last = self.lastPosted,
                      hypot(current.x - last.x, current.y - last.y) < 3 else { return }
                self.post(at: target, edge: geometry.edge, source: source)
            }
        }
        return true
    }

    private func post(at point: CGPoint, edge: DockEdge, source: CGEventSource) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: eventTag)
        event.setIntegerValueField(.mouseEventDeltaX, value: edge == .left ? -8 : edge == .right ? 8 : 0)
        event.setIntegerValueField(.mouseEventDeltaY, value: edge == .bottom ? 8 : 0)
        CGWarpMouseCursorPosition(point)
        lastPosted = point
        event.post(tap: .cgSessionEventTap)
    }

    private func restorePointer() {
        if let original, let lastPosted, let current = CGEvent(source: nil)?.location,
           hypot(current.x - lastPosted.x, current.y - lastPosted.y) < 3 {
            CGWarpMouseCursorPosition(original)
        }
        original = nil
        lastPosted = nil
        if mouseHidden { NSCursor.unhide(); mouseHidden = false }
    }
}
