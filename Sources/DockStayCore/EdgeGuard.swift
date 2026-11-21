import Foundation
import CoreGraphics

public enum DockEdge: String, Sendable {
    case bottom, left, right
}

public struct Display: Equatable, Sendable {
    public let id: String
    public let bounds: CGRect

    public init(id: String, bounds: CGRect) {
        self.id = id
        self.bounds = bounds
    }
}

/// All geometry uses Quartz global coordinates: origin at the main display's top left.
public struct EdgeGuard: Sendable {
    public var displays: [Display]
    public var selectedID: String?
    public var edge: DockEdge
    public let inset: CGFloat = 4

    public init(displays: [Display] = [], selectedID: String? = nil, edge: DockEdge = .bottom) {
        self.displays = displays
        self.selectedID = selectedID
        self.edge = edge
    }

    public func constrained(_ point: CGPoint) -> CGPoint {
        guard displays.count > 1,
              displays.contains(where: { $0.id == selectedID }),
              let display = displays.first(where: { $0.bounds.contains(point) }),
              display.id != selectedID else { return point }

        let rect = display.bounds
        let coordinate: CGFloat
        let nearEdge: Bool
        var result = point
        switch edge {
        case .bottom:
            coordinate = point.x
            nearEdge = point.y > rect.maxY - inset
            result.y = rect.maxY - inset
        case .left:
            coordinate = point.y
            nearEdge = point.x < rect.minX + inset
            result.x = rect.minX + inset
        case .right:
            coordinate = point.y
            nearEdge = point.x > rect.maxX - inset
            result.x = rect.maxX - inset
        }
        guard nearEdge,
              exposedSegments(of: display).contains(where: { $0.contains(coordinate) }) else {
            return point
        }
        return result
    }

    /// A point on a real outer edge, away from hot corners and inter-display passages.
    public func activationPoint(for display: Display) -> CGPoint? {
        guard let segment = exposedSegments(of: display)
            .filter({ $0.upperBound - $0.lowerBound > 24 })
            .max(by: { $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound }) else {
            return nil
        }
        let middle = (segment.lowerBound + segment.upperBound) / 2
        switch edge {
        case .bottom: return CGPoint(x: middle, y: display.bounds.maxY - 1)
        case .left: return CGPoint(x: display.bounds.minX, y: middle)
        case .right: return CGPoint(x: display.bounds.maxX - 1, y: middle)
        }
    }

    public func exposedSegments(of display: Display) -> [Range<CGFloat>] {
        let rect = display.bounds
        var segments: [Range<CGFloat>] = edge == .bottom
            ? [rect.minX..<rect.maxX] : [rect.minY..<rect.maxY]

        for other in displays where other.id != display.id {
            let neighbor = other.bounds
            let touches: Bool
            let covered: Range<CGFloat>
            switch edge {
            case .bottom:
                touches = neighbor.minY <= rect.maxY && neighbor.maxY > rect.maxY
                covered = neighbor.minX..<neighbor.maxX
            case .left:
                touches = neighbor.minX < rect.minX && neighbor.maxX >= rect.minX
                covered = neighbor.minY..<neighbor.maxY
            case .right:
                touches = neighbor.minX <= rect.maxX && neighbor.maxX > rect.maxX
                covered = neighbor.minY..<neighbor.maxY
            }
            guard touches else { continue }
            segments = segments.flatMap { segment -> [Range<CGFloat>] in
                let lower = max(segment.lowerBound, covered.lowerBound)
                let upper = min(segment.upperBound, covered.upperBound)
                guard lower < upper else { return [segment] }
                var remaining: [Range<CGFloat>] = []
                if segment.lowerBound < lower { remaining.append(segment.lowerBound..<lower) }
                if upper < segment.upperBound { remaining.append(upper..<segment.upperBound) }
                return remaining
            }
        }
        return segments
    }
}
