// How a body walks past another: the rule apart from the picture, no SceneKit.
//
// Bodies walk their line exactly and never stop for anybody; the model knows nothing of shoulders.
// What passing changes is only how the figure is drawn: someone close ahead makes the walker turn to
// face them and lean a shoulder to its own right for the length of the pass, like two broad
// shoulders in a doorway, then it faces its way again. Tested by `--walk-tests`.

import Foundation

enum Walk {
    /// Someone within this of the walker, and not behind it, is being passed: far enough for the awkward moment.
    static let reach = 1.0
    /// A pass begun is held until the other is this far behind, so it never flickers when the two are abreast.
    static let behind = 0.35
    /// How far the figure leans off its line while passing: a shoulder's width.
    static let sidestep = 0.16
    /// Within this of a waypoint counts as there.
    static let arrive = 0.08
    /// The pass is driven by the gap to the other, no clock: from `reach` in, slow down and turn to face them;
    /// from `leanFrom` in, slide out; behind, straighten up and stride on.
    static let leanFrom = 0.5
    /// The pace while passing, of the walk's own.
    static let slowTo = 0.35

    /// The body being passed this tick, if any: close and not behind.
    static func passing(_ m: Body, target: SIMD2<Double>, others: [Body]) -> Body? {
        let line = target - m.pos
        let len = (line.x * line.x + line.y * line.y).squareRoot()
        guard len > 1e-6 else { return nil }
        let dir = line / len
        // The one already being passed is kept until clearly behind or gone; only then is anyone else looked at.
        if let id = m.passingId, let o = others.first(where: { $0.id == id }) {
            let along = (o.pos.x - m.pos.x) * dir.x + (o.pos.y - m.pos.y) * dir.y
            if along > -behind, dist2(o.pos, m.pos) < reach * reach * 1.5 { return o }
        }
        m.passingId = nil
        let found = others.min { a, b in dist2(a.pos, m.pos) < dist2(b.pos, m.pos) }.flatMap { o -> Body? in
            let ahead = (o.pos.x - m.pos.x) * dir.x + (o.pos.y - m.pos.y) * dir.y > 0
            return ahead && dist2(o.pos, m.pos) < reach * reach ? o : nil
        }
        m.passingId = found?.id
        return found
    }

    /// One tick of one walker toward the first waypoint of its path: moves it along its line, pops the
    /// waypoint on arrival, plays the pass on its clock, and says who was being passed.
    static func step(_ m: Body, speed: Double, dt: Double, others: [Body]) -> Body? {
        guard let target = m.path.first else { m.lean = .zero; m.passingId = nil; return nil }
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
        // A walk that ends ends straight: whatever the pass was doing, the figure faces the way it came
        // and stands square; nobody is left half-turned toward someone who happened to be near.
        if m.path.isEmpty {
            m.lean = .zero
            m.passingId = nil
            if dist > 1e-9 { m.facing = atan2(d.x, d.y) }
            return nil
        }
        if let near, dist > 1e-9 {
            let dir = d / dist
            // 2. A quarter turn side-on, toward the side the other goes by on, the walker's left, so the
            // shoulders lie along the line; 3. then, closer, slide a shoulder out to the right and pass.
            m.facing = atan2(-dir.y, dir.x)
            let out = min(1, max(0, (leanFrom - gap) / (leanFrom - sidestep)))
            m.lean = SIMD2(dir.y, -dir.x) * (sidestep * out)
        } else {
            // 4. Face the way again and 5. stride on; the scene eases the lean away.
            m.lean = .zero
            if dist > 1e-9 { m.facing = atan2(d.x, d.y) }
        }
        return near
    }

    private static func dist2(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) }
}
