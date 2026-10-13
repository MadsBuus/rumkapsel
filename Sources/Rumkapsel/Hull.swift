import Foundation
import simd

struct StationHull {
    static let section = Classic.hullSection(depth: Station.hullDepth)
    static let doorTop = 1.0

    struct Foot { let a: SIMD2<Double>, b: SIMD2<Double>; let door: Bool }

    let inside: Set<Cell>
    let feet: [Foot]
    private let near: [Cell: [Int]]

    init(_ st: Station) {
        let b = st.bounds
        let pad = Set(st.hall.padCells), bay = Set(st.hangarCells)
        let beyond = st.walkable.subtracting(bay).subtracting(pad).map(\.y).max() ?? Int.max
        var inside = bay
        for x in b.min.x...b.max.x {
            for y in b.min.y...b.max.y where y <= beyond && !pad.contains(Cell(x: x, y: y)) { inside.insert(Cell(x: x, y: y)) }
        }
        var doors = Set<[Int]>()
        for (hall, out) in st.hall.padWall { doors.insert([hall.x, hall.y, out.x, out.y]) }
        if let mouth = st.hangarCells.map(\.y).max() {
            for c in st.hangarCells where c.y == mouth { doors.insert([c.x, c.y, c.x, c.y + 1]) }
        }
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

    func reach(_ p: SIMD2<Double>, doors: Bool = true) -> (distance: Double, door: Bool) {
        var best = (distance: StationHull.section.lean, door: false)
        let candidates = near[Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded()))] ?? Array(feet.indices)
        for i in candidates where doors || !feet[i].door {
            let d = StationHull.distance(p, to: feet[i])
            if d < best.distance { best = (d, feet[i].door) }
        }
        return best
    }

    func nearDoor(_ c: Cell) -> Bool { near[c]?.contains { feet[$0].door } ?? false }

    static func height(atDistance d: Double) -> Double {
        let (lean, rise) = section
        let k = min(1, max(0, d / lean))
        return rise * (1 - (1 - k) * (1 - k)).squareRoot()
    }

    func roof(over p: SIMD2<Double>, top: Double) -> Double? {
        guard covers(p) else { return nil }
        let r = reach(p, doors: true)
        if r.door, top < StationHull.doorTop { return StationHull.height(atDistance: reach(p, doors: false).distance) }
        return StationHull.height(atDistance: r.distance)
    }
}
