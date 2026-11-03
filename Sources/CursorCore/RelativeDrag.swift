import Foundation

/// Estimated relative movement for a touch held by the relative mouse collection.
/// iOS acceleration varies; this is a prior, not device-calibrated positioning.
public struct RelativeDrag {
    public struct Delta: Equatable { public let x: Int; public let y: Int }
    // Measured on a 750px-wide reference iPhone; adapted from MIT iPhone Use.
    // See THIRD_PARTY_NOTICES.md. Use screen-width-normalized units for both axes.
    private static let distances: [Double] = [
        0,0.53125,1.28125,2.1875,3.28125,4.5625,6.03125,7.65625,
        9.5,11.508771929824562,13.708333333333334,16.1,18.647058823529413,
        21.4,24.37037037037037,27.47826086956522,30.761904761904763,
        34.31578947368421,38,41.86666666666667,46,50.15384615384615,
        54.72727272727273,59.2,64.2,69.11111111111111,74.25,79.75,
        85.42857142857143,91.14285714285714,97.33333333333333,
        103.33333333333333,109.6
    ]
    private var x: Double
    private var y: Double
    private let height: Double
    public init(start: Pointer, aspectRatio: Double) {
        let aspect = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 393.0 / 852.0
        height = 750 / min(5, max(0.2, aspect))
        x = start.x * 750; y = start.y * height
    }
    public var estimatedPointer: Pointer { Pointer(x: x / 750, y: y / height) }
    public mutating func move(to target: Pointer) -> [Delta] {
        let tx = target.x * 750, ty = target.y * height
        let tolerance = Self.distances[1] / 2
        var result: [Delta] = []
        // Bounded even for a full-screen jump on the tallest supported aspect.
        for _ in 0..<64 {
            let ex = tx - x, ey = ty - y
            guard max(abs(ex), abs(ey)) > tolerance else { break }
            let horizontal = abs(ex) >= abs(ey)
            let error = horizontal ? ex : ey
            let magnitude = (1..<Self.distances.count).last {
                Self.distances[$0] <= abs(error) + tolerance
            } ?? 1
            let count = error < 0 ? -magnitude : magnitude
            let distance = Self.distances[magnitude] * (error < 0 ? -1 : 1)
            if horizontal { x += distance; result.append(Delta(x: count, y: 0)) }
            else { y += distance; result.append(Delta(x: 0, y: count)) }
        }
        return result
    }
}
