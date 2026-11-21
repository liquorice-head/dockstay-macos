import Foundation
import CoreGraphics
import Testing
@testable import DockStayCore

private let main = Display(id: "main", bounds: CGRect(x: 0, y: 0, width: 1440, height: 900))
private let right = Display(id: "right", bounds: CGRect(x: 1440, y: 0, width: 1920, height: 1080))

@Test func selectedDisplayIsNeverRestricted() {
    let guarder = EdgeGuard(displays: [main, right], selectedID: "main")
    let point = CGPoint(x: 700, y: 899)
    #expect(guarder.constrained(point) == point)
}

@Test func blocksOnlyLastFourPointsOfOtherDisplay() {
    let guarder = EdgeGuard(displays: [main, right], selectedID: "main")
    #expect(guarder.constrained(CGPoint(x: 2000, y: 1079)) == CGPoint(x: 2000, y: 1076))
    #expect(guarder.constrained(CGPoint(x: 2000, y: 1075)) == CGPoint(x: 2000, y: 1075))
}

@Test func missingSelectionAndDisconnectedTargetFailOpen() {
    let point = CGPoint(x: 2000, y: 1079)
    for selection: String? in [nil, "", "disconnected"] {
        #expect(EdgeGuard(displays: [main, right], selectedID: selection).constrained(point) == point)
    }
}

@Test func oneDisplayIsNeverRestricted() {
    let guarder = EdgeGuard(displays: [main], selectedID: "main")
    #expect(guarder.constrained(CGPoint(x: 300, y: 899)) == CGPoint(x: 300, y: 899))
}

@Test func preservesPassageToStackedDisplay() {
    let below = Display(id: "below", bounds: CGRect(x: 500, y: 900, width: 940, height: 800))
    let guarder = EdgeGuard(displays: [main, below], selectedID: "below")
    #expect(guarder.constrained(CGPoint(x: 700, y: 899)) == CGPoint(x: 700, y: 899))
    #expect(guarder.constrained(CGPoint(x: 200, y: 899)) == CGPoint(x: 200, y: 896))
    #expect(guarder.activationPoint(for: main) == CGPoint(x: 250, y: 899))
}

@Test func fullWidthStackedNeighborLeavesNoActivationPoint() {
    let below = Display(id: "below", bounds: CGRect(x: 0, y: 900, width: 1440, height: 900))
    let guarder = EdgeGuard(displays: [main, below], selectedID: "below")
    #expect(guarder.activationPoint(for: main) == nil)
    #expect(guarder.constrained(CGPoint(x: 700, y: 899)) == CGPoint(x: 700, y: 899))
}

@Test func subtractsMultipleNeighborsFromAnEdge() {
    let lowerLeft = Display(id: "lowerLeft", bounds: CGRect(x: 0, y: 900, width: 400, height: 700))
    let lowerRight = Display(id: "lowerRight", bounds: CGRect(x: 1000, y: 900, width: 800, height: 700))
    let guarder = EdgeGuard(displays: [main, lowerLeft, lowerRight], selectedID: "lowerLeft")
    #expect(guarder.exposedSegments(of: main) == [400..<1000])
    #expect(guarder.activationPoint(for: main) == CGPoint(x: 700, y: 899))
}

@Test func handlesDisplaysAboveAndLeftOfMain() {
    let upperLeft = Display(id: "negative", bounds: CGRect(x: -1920, y: -1080, width: 1920, height: 1080))
    let guarder = EdgeGuard(displays: [main, upperLeft], selectedID: "main")
    #expect(guarder.constrained(CGPoint(x: -900, y: -1)) == CGPoint(x: -900, y: -4))
}

@Test func sideEdgesUseQuartzCoordinates() {
    let leftGuard = EdgeGuard(displays: [main, right], selectedID: "right", edge: .left)
    #expect(leftGuard.constrained(CGPoint(x: 0, y: 300)) == CGPoint(x: 4, y: 300))
    let rightGuard = EdgeGuard(displays: [main, right], selectedID: "main", edge: .right)
    #expect(rightGuard.constrained(CGPoint(x: 3359, y: 300)) == CGPoint(x: 3356, y: 300))
}

@Test func sideBySidePassageIsNotBlockedBySideDock() {
    let rightGuard = EdgeGuard(displays: [main, right], selectedID: "right", edge: .right)
    #expect(rightGuard.constrained(CGPoint(x: 1439, y: 400)) == CGPoint(x: 1439, y: 400))
    #expect(rightGuard.activationPoint(for: main) == nil)
}

@Test func passageEndpointIsNotTreatedAsCovered() {
    let below = Display(id: "below", bounds: CGRect(x: 500, y: 900, width: 500, height: 800))
    let guarder = EdgeGuard(displays: [main, below], selectedID: "below")
    #expect(guarder.constrained(CGPoint(x: 999, y: 899)) == CGPoint(x: 999, y: 899))
    #expect(guarder.constrained(CGPoint(x: 1000, y: 899)) == CGPoint(x: 1000, y: 896))
}

@Test func pointsOutsideKnownScreensAreNotWarped() {
    let guarder = EdgeGuard(displays: [main, right], selectedID: "main")
    let point = CGPoint(x: 9000, y: 9000)
    #expect(guarder.constrained(point) == point)
}
