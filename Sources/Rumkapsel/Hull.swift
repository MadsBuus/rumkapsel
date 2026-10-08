// The station's hull: one vault over everything indoors, with the pad and the bay left outside under open
// space. The pieces of it drawn in the station's view, at the airlock's outer door and along the pad, are
// where it meets the floor; walking, the whole of it is overhead.

import Foundation
import simd

struct StationHull {
    /// How far the hull leans in from where it meets the floor, and how high its crown stands: the same
    /// section as the pieces of it at the airlock and the pad, so the three are one surface.
    static let section = Classic.hullSection(depth: Double(Station.airlockLength))
    /// How high a doorway through it is cut.
    static let doorTop = 1.0

    /// One stretch of where the hull meets the floor, along a cell's side, in the station's own cells.
    struct Foot { let a: SIMD2<Double>, b: SIMD2<Double>; let door: Bool }

    /// The cells under the hull, every stretch of its foot, and for each cell the stretches near enough to
    /// shape the hull over it: the rest are further than it leans, where it is at its crown.
    let inside: Set<Cell>
    let feet: [Foot]
    private let near: [Cell: [Int]]

    /// Indoors is the station's whole extent but the pad and the bay: the bay beyond the airlock's outer
    /// door, the pad where the yard opens to space. The gate onto the pad and the airlock's outer door are
    /// doorways through it.
    init(_ st: Station) {
        let b = st.bounds
        let pad = Set(st.padCells)
        let outerDoor = st.airlockCells.max { $0.y < $1.y }
        let beyond = outerDoor?.y ?? Int.max
        var inside = Set<Cell>()
        for x in b.min.x...b.max.x {
            for y in b.min.y...b.max.y where y <= beyond && !pad.contains(Cell(x: x, y: y)) { inside.insert(Cell(x: x, y: y)) }
        }
        var doors = Set<[Int]>()
        for (deck, padCell) in st.gateDoorway { doors.insert([deck.x, deck.y, padCell.x, padCell.y]) }
        if let o = outerDoor { doors.insert([o.x, o.y, o.x, o.y + 1]) }
        var feet: [Foot] = []
        var footOf: [Cell: [Int]] = [:]
        for c in inside {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !inside.contains(Cell(x: c.x + dx, y: c.y + dy)) {
                let mid = SIMD2(Double(c.x) + Double(dx) / 2, Double(c.y) + Double(dy) / 2)
                let along = SIMD2(Double(dy), Double(dx)) / 2
                footOf[c, default: []].append(feet.count)
                feet.append(Foot(a: mid - along, b: mid + along, door: doors.contains([c.x, c.y, c.x + dx, c.y + dy])))
            }
        }
        let lean = StationHull.section.lean, span = Int(lean.rounded(.up)) + 1
        var near: [Cell: [Int]] = [:]
        for c in inside {
            var mine: [Int] = []
            for x in -span...span { for y in -span...span {
                for i in footOf[Cell(x: c.x + x, y: c.y + y)] ?? [] where StationHull.distance(SIMD2(Double(c.x), Double(c.y)), to: feet[i]) <= lean + 0.75 {
                    mine.append(i)
                }
            } }
            near[c] = mine
        }
        self.inside = inside
        self.feet = feet
        self.near = near
    }

    private static func distance(_ p: SIMD2<Double>, to f: Foot) -> Double {
        let ab = f.b - f.a, t = max(0, min(1, simd_dot(p - f.a, ab) / simd_dot(ab, ab)))
        return simd_length(p - (f.a + ab * t))
    }

    func covers(_ p: SIMD2<Double>) -> Bool { inside.contains(Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded()))) }

    /// How far a point is from the hull's foot, and whether that nearest stretch is a doorway: as far as it
    /// leans at most, where it is at its crown.
    func reach(_ p: SIMD2<Double>, doors: Bool = true) -> (distance: Double, door: Bool) {
        var best = (distance: StationHull.section.lean, door: false)
        let candidates = near[Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded()))] ?? Array(feet.indices)
        for i in candidates where doors || !feet[i].door {
            let d = StationHull.distance(p, to: feet[i])
            if d < best.distance { best = (d, feet[i].door) }
        }
        return best
    }

    /// Whether a doorway's foot is near enough to a cell to shape the hull over it.
    func nearDoor(_ c: Cell) -> Bool { near[c]?.contains { feet[$0].door } ?? false }

    /// How high the hull stands over a point indoors: the quarter ellipse of its section, upright where it
    /// meets the floor and lying flat once it is in as far as it leans.
    static func height(atDistance d: Double) -> Double {
        let (lean, rise) = section
        let k = min(1, max(0, d / lean))
        return rise * (1 - (1 - k) * (1 - k)).squareRoot()
    }

    /// The room over a point for something whose top is `top` off the floor: nil under open space, else how
    /// high the hull is there. Low enough to go through a doorway, a doorway's foot does not count.
    func roof(over p: SIMD2<Double>, top: Double) -> Double? {
        guard covers(p) else { return nil }
        let r = reach(p, doors: true)
        if r.door, top < StationHull.doorTop { return StationHull.height(atDistance: reach(p, doors: false).distance) }
        return StationHull.height(atDistance: r.distance)
    }
}
