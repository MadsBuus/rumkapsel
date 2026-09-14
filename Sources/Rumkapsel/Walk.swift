// How a body walks past another: the rule apart from the picture, no SceneKit.
//
// Bodies walk their line exactly and never stop for anybody; the model knows nothing of shoulders.
// What passing changes is only how the figure is drawn: someone close ahead makes the walker turn to
// face them and lean a shoulder to its own right for the length of the pass, like two broad
// shoulders in a doorway, then it faces its way again. Tested by `--walk-tests`.

import Foundation

enum Walk {
    /// Someone within this of the walker, and not behind it, is being passed: far enough for the awkward moment.
    static let reach = 0.8
    /// How far the figure leans off its line while passing: a shoulder's width.
    static let sidestep = 0.24
    /// Within this of a waypoint counts as there.
    static let arrive = 0.08
    /// The pass is driven by the gap to the other, no clock: from `reach` in, slow down and turn to face them;
    /// from `leanFrom` in, lean out and wriggle past; behind, straighten up and stride on.
    static let leanFrom = 0.5
    /// The pace while passing, of the walk's own.
    static let slowTo = 0.4

    /// The body being passed this tick, if any: close and not behind.
    static func passing(_ m: Body, target: SIMD2<Double>, others: [Body]) -> Body? {
        let line = target - m.pos
        let len = (line.x * line.x + line.y * line.y).squareRoot()
        guard len > 1e-6 else { return nil }
        let dir = line / len
        return others.min { a, b in dist2(a.pos, m.pos) < dist2(b.pos, m.pos) }.flatMap { o -> Body? in
            let ahead = (o.pos.x - m.pos.x) * dir.x + (o.pos.y - m.pos.y) * dir.y > -0.1
            return ahead && dist2(o.pos, m.pos) < reach * reach ? o : nil
        }
    }

    /// One tick of one walker toward the first waypoint of its path: moves it along its line, pops the
    /// waypoint on arrival, plays the pass on its clock, and says who was being passed.
    static func step(_ m: Body, speed: Double, dt: Double, others: [Body]) -> Body? {
        guard let target = m.path.first else { m.lean = .zero; return nil }
        let d = target - m.pos
        let dist = (d.x * d.x + d.y * d.y).squareRoot()
        let near = passing(m, target: target, others: others)
        let gap = near.map { dist2($0.pos, m.pos).squareRoot() } ?? reach
        // 1. Slow down as the gap closes: an awkward moment.
        let closing = min(1, max(0, (reach - gap) / (reach - leanFrom)))
        let pace = 1 - (1 - slowTo) * closing
        let stride = speed * pace * dt
        m.pos = dist <= stride ? target : m.pos + d / dist * stride
        if dist2(target, m.pos) < arrive * arrive { m.pos = target; m.path.removeFirst() }
        if let near, dist > 1e-9 {
            let dir = d / dist
            // 2. Turn to face the other, 3. then, closer, lean a shoulder to the walker's own right and wriggle past.
            m.facing = atan2(near.pos.x - m.pos.x, near.pos.y - m.pos.y)
            let out = min(1, max(0, (leanFrom - gap) / (leanFrom - sidestep)))
            let wriggle = out > 0 ? sin(gap * 40) * 0.03 : 0
            m.lean = SIMD2(dir.y, -dir.x) * (sidestep * out) + dir * wriggle
        } else {
            // 4. Face the way again and 5. stride on; the scene eases the lean away.
            m.lean = .zero
            if dist > 1e-9 { m.facing = atan2(d.x, d.y) }
        }
        return near
    }

    private static func dist2(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) }
}
