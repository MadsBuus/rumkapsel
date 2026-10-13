import Foundation

enum Walk {
    static let reach = 1.0
    static let behind = 0.35
    static let sidestep = 0.16
    static let arrive = 0.08
    static let leanFrom = 0.5
    static let slowTo = 0.35
    static let stepBack = 0.1
    static let lane = 0.45
    static let budget = 1.2

    static func passing(_ m: Body, target: SIMD2<Double>, others: [Body]) -> Body? {
        let line = target - m.pos
        let len = (line.x * line.x + line.y * line.y).squareRoot()
        guard len > 1e-6 else { return nil }
        let dir = line / len
        if let id = m.passingId, let o = others.first(where: { $0.id == id }) {
            let along = (o.pos.x - m.pos.x) * dir.x + (o.pos.y - m.pos.y) * dir.y
            if m.passWalked >= budget { m.passedId = id }
            else if along > -behind, dist2(o.pos, m.pos) < reach * reach * 1.5 { return o }
        }
        m.passingId = nil
        m.passWalked = 0
        if let done = m.passedId, !others.contains(where: { $0.id == done && dist2($0.pos, m.pos) < reach * reach * 1.5 }) { m.passedId = nil }
        let found = others.filter { o in
            guard o.id != m.passedId else { return false }
            let to = o.pos - m.pos
            let along = to.x * dir.x + to.y * dir.y
            let across = abs(to.x * dir.y - to.y * dir.x)
            return along > 0 && across < lane && dist2(o.pos, m.pos) < reach * reach
        }.min { dist2($0.pos, m.pos) < dist2($1.pos, m.pos) }
        m.passingId = found?.id
        return found
    }

    static func step(_ m: Body, speed: Double, dt: Double, others: [Body]) -> Body? {
        guard let target = m.path.first else { m.lean = .zero; m.passingId = nil; m.passedId = nil; m.passWalked = 0; return nil }
        let d = target - m.pos
        let dist = (d.x * d.x + d.y * d.y).squareRoot()
        let near = passing(m, target: target, others: others)
        let gap = near.map { dist2($0.pos, m.pos).squareRoot() } ?? reach
        let closing = min(1, max(0, (reach - gap) / (reach - leanFrom)))
        let pace = 1 - (1 - slowTo) * closing
        let stride = speed * pace * dt
        m.pos = dist <= stride ? target : m.pos + d / dist * stride
        if near != nil { m.passWalked += min(stride, dist) }
        if dist2(target, m.pos) < arrive * arrive { m.pos = target; m.path.removeFirst() }
        if m.path.isEmpty {
            m.lean = .zero
            m.passingId = nil
            m.passedId = nil
            m.passWalked = 0
            if dist > 1e-9 { m.facing = atan2(d.x, d.y) }
            return nil
        }
        if let near, dist > 1e-9 {
            let dir = d / dist
            m.facing = atan2(-dir.y, dir.x)
            let out = min(1, max(0, (leanFrom - gap) / (leanFrom - sidestep)))
            m.lean = SIMD2(dir.y, -dir.x) * (sidestep * out) - dir * (stepBack * closing * (1 - out))
        } else {
            m.lean = .zero
            if dist > 1e-9 { m.facing = atan2(d.x, d.y) }
        }
        return near
    }

    private static func dist2(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) }
}
