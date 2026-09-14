// How a body walks past another: the rule apart from the picture, no SceneKit.
//
// A walker who finds someone in its way, standing or coming, aims a third of a tile to its own
// right of the next waypoint, passes, and aims back at the waypoint once they are behind. The
// other does the same, so two head-on pass on their right. Where the right is not walkable the
// walker keeps its line and walks on; nobody ever stops for anybody, so two bodies may overlap for
// a moment there, and nothing can deadlock. Tested by `--walk-tests`.

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
    /// who that someone is; and the sideways direction away from them, zero when no side is walkable.
    /// `others` are the solid bodies on the same station, the walker excluded.
    static func aim(_ m: Body, target: SIMD2<Double>, others: [Body], station: Station) -> (aim: SIMD2<Double>, near: Body?, side: SIMD2<Double>) {
        let line = target - m.pos
        let len = (line.x * line.x + line.y * line.y).squareRoot()
        guard len > 1e-6 else { return (target, nil, .zero) }
        let dir = line / len
        // In the way: near the waypoint or near the walker, and not behind.
        let near = others.min { a, b in dist2(a.pos, m.pos) < dist2(b.pos, m.pos) }.flatMap { o -> Body? in
            let ahead = (o.pos.x - m.pos.x) * dir.x + (o.pos.y - m.pos.y) * dir.y > -0.1
            let close = dist2(o.pos, target) < reach * reach || dist2(o.pos, m.pos) < reach * reach
            return ahead && close ? o : nil
        }
        guard let near else { m.passDir = nil; return (target, nil, .zero) }
        // Always to the walker's own right of the bearing it had when the pass began: the bearing to a near
        // waypoint swings as the walker closes in, and a spot that swung with it could never be reached.
        let held = m.passDir ?? dir
        m.passDir = held
        let right = SIMD2(held.y, -held.x)
        let spot = target + right * sidestep
        let cell = Cell(x: Int(spot.x.rounded()), y: Int(spot.y.rounded()))
        if station.walkable.contains(cell), !station.obstacles.contains(Station.sub(spot)) { return (spot, near, right) }
        return (target, near, .zero)
    }

    /// One tick of one walker toward the first waypoint of its path: moves it, pops the waypoint on
    /// arrival, and says who was in the way. The scene calls this and nothing else moves a walker.
    static func step(_ m: Body, speed: Double, dt: Double, others: [Body], station: Station) -> Body? {
        guard let target = m.path.first else { return nil }
        let (aim, near, _) = Walk.aim(m, target: target, others: others, station: station)
        let d = aim - m.pos
        let dist = (d.x * d.x + d.y * d.y).squareRoot()
        let stride = speed * dt
        m.pos = dist <= stride ? aim : m.pos + d / dist * stride
        // There: at the waypoint, or at the fixed spot beside it while someone is in the way.
        if dist2(aim, m.pos) < arrive * arrive {
            if near == nil { m.pos = target }
            m.path.removeFirst()
        }
        // Passing, the body turns to face the one it passes and slides by sideways, like two broad
        // shoulders in a doorway; clear again, it faces the way it walks.
        if let near { m.facing = atan2(near.pos.x - m.pos.x, near.pos.y - m.pos.y) }
        else if dist > 1e-9 { m.facing = atan2(d.x, d.y) }
        return near
    }

    private static func dist2(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) }
}
