import Foundation

extension Simulation {
    func freeAnchors(_ m: B, station: Station, in room: String) -> [FixtureRef] {
        let taken = Set(bodies.values.filter { $0.id != m.id && $0.station == m.station }.compactMap(\.using))
        return station.anchors(in: room).filter { !taken.contains($0) }
    }

    @discardableResult
    func use(_ m: B, _ ref: FixtureRef, station: Station, seconds: Double) -> Bool {
        guard let place = station.place(ref), let kind = station.fixtures(in: ref.room)[safe: ref.fixture]?.kind else { return false }
        let back = m.place
        guard start(m, .use(ref, kind: kind, back: back, seconds: seconds), announce: true), m.using == ref else { return false }
        m.couch = nil
        m.place = .room(ref.room)
        let near = place.use == .stand ? place.at + place.outward * Hands.arm : place.at
        m.path = route(m, to: standCell(station, near: Cell(x: Int(near.x.rounded()), y: Int(near.y.rounded()))))
        return true
    }

    func stepUse(_ m: B, station: Station, dt: Double) -> Bool {
        guard let ref = m.using, m.path.isEmpty, m.phaseKind == .act, let place = station.place(ref) else { return false }
        if !m.inPlace {
            switch place.use {
            case .stand:
                guard atArmsLength(m, of: place.at, from: place.outward, square: true, dt: dt) else { return true }
                m.settledOn = (ref, nil)
            case .sit(let height):
                guard sit(m, at: place.at, facing: place.facing, dt: dt) else { return true }
                m.settledOn = (ref, height)
            }
            m.actStartedAt = clock
            m.phaseUntil = clock + m.actFor
        }
        guard clock >= m.phaseUntil else { return false }
        var back = restPlace(m)
        if !m.busy, case .use(_, _, let where_, _) = m.current?.kind { back = where_ }
        visitDone(m, ref.room)
        finish(m, to: back)
        return true
    }

    func sit(_ m: B, at seat: SIMD2<Double>, facing: Double, dt: Double) -> Bool {
        m.facing = facing
        let d = seat - m.pos
        if (d.x * d.x + d.y * d.y).squareRoot() <= 0.02 { m.pos = seat; return true }
        m.pos += d * min(1, dt * 6)
        return false
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
