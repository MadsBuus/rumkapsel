// How a body walks past another: the rule apart from the picture, no SceneKit.
//
// Bodies are solid at the middle of their tile. A walker who finds someone in its way, standing or
// coming, aims a third of a tile to the side of its next waypoint, on the side away from them,
// passes, and aims back at the waypoint once they are behind. The other does the same. Where no
// side is walkable, the walker keeps its line and holds still until the way is clear. Nobody
// waits on a clock, plans again or claims anything. Tested by `--walk-tests`.

import Foundation

enum Walk {
    /// How close two bodies may come, centre to centre.
    static let solid = 0.26
    /// How far off the line a walker drifts to pass.
    static let sidestep = 0.34
    /// Within this of a waypoint counts as there, so a passing walker never has to touch the exact centre.
    static let arrive = 0.08
    /// Someone within this of the next waypoint, or of the walker, is in the way.
    static let reach = 0.6

    /// Where to head this tick: the waypoint itself, or a spot beside it while someone is in the way;
    /// and who that someone is. `others` are the solid bodies on the same station, the walker excluded.
    static func aim(_ m: Body, target: SIMD2<Double>, others: [Body], station: Station) -> (SIMD2<Double>, Body?) {
        let line = target - m.pos
        let len = (line.x * line.x + line.y * line.y).squareRoot()
        guard len > 1e-6 else { return (target, nil) }
        let dir = line / len
        // In the way: near the waypoint or near the walker, and not behind.
        let near = others.min { a, b in dist2(a.pos, m.pos) < dist2(b.pos, m.pos) }.flatMap { o -> Body? in
            let ahead = (o.pos.x - m.pos.x) * dir.x + (o.pos.y - m.pos.y) * dir.y > -0.1
            let close = dist2(o.pos, target) < reach * reach || dist2(o.pos, m.pos) < reach * reach
            return ahead && close ? o : nil
        }
        guard let near else { return (target, nil) }
        let right = SIMD2(dir.y, -dir.x)
        let toThem = (near.pos.x - m.pos.x) * right.x + (near.pos.y - m.pos.y) * right.y
        let away = toThem > 0 ? -1.0 : 1.0
        for side in [away, -away] {
            let spot = target + right * (side * sidestep)
            let cell = Cell(x: Int(spot.x.rounded()), y: Int(spot.y.rounded()))
            if station.walkable.contains(cell), !station.obstacles.contains(Station.sub(spot)) { return (spot, near) }
        }
        return (target, near)
    }

    private static func dist2(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) }
}
