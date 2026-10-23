import simd
import Foundation

extension Simulation {
    func freeAnchors(_ m: B, station: Station, in room: String) -> [FixtureRef] {
        let taken = Set(bodies.values.filter { $0.id != m.id && $0.station == m.station }.compactMap(\.using))
        return station.anchors(in: room).filter { !taken.contains($0) }
    }

    @discardableResult
    func use(_ m: B, _ ref: FixtureRef, station: Station, seconds: Double, back: Place? = nil) -> Bool {
        guard let place = station.place(ref), let kind = station.fixtures(in: ref.room)[safe: ref.fixture]?.kind,
              let room = station.rooms[ref.room] else { return false }
        let back = back ?? m.place
        guard start(m, .use(ref, kind: kind, back: back, seconds: seconds), announce: true), m.using == ref else { return false }
        m.couch = nil
        m.place = .room(ref.room)
        let last = place.use == .stand ? place.at + place.outward * Hands.arm : place.stand
        m.path = route(m, to: standCell(station, near: last, within: Set(room.cells))) + [last]
        return true
    }

    func stepUse(_ m: B, station: Station, dt: Double) -> Bool {
        guard let ref = m.using, let order = m.current?.id, m.path.isEmpty, m.phaseKind == .act, let place = station.place(ref) else { return false }
        if !m.inPlace {
            if place.use == .stand, !atArmsLength(m, of: place.at, from: place.outward, square: true, dt: dt) { return true }
            m.settledOn = (order, nil)
            m.actStartedAt = clock
            m.phaseUntil = clock + m.actFor
        }
        if case .sit(let height) = place.use {
            let s = place.sitting(clock - m.actStartedAt, of: m.actFor)
            m.pos = s.pos
            m.facing = s.facing
            m.settledOn = (order, s.down ? height : nil)
        }
        guard clock >= m.phaseUntil else { return false }
        var back = restPlace(m)
        if !m.busy, case .use(_, _, let where_, _) = m.current?.kind { back = where_ }
        if let fare = m.fare { served(m, fare) }
        visitDone(m, ref.room)
        finish(m, to: back)
        return true
    }

    func standCell(_ st: Station, near point: SIMD2<Double>, within cells: Set<Cell>) -> Cell {
        let clear = cells.filter { c in (-1...1).allSatisfy { dx in (-1...1).allSatisfy { dy in !st.obstacles.contains(Cell(x: c.x * Station.fine + dx, y: c.y * Station.fine + dy)) } } }
        let pool = clear.isEmpty ? cells : clear
        return pool.min { a, b in
            (simd_distance(SIMD2(Double(a.x), Double(a.y)), point), a.x, a.y) < (simd_distance(SIMD2(Double(b.x), Double(b.y)), point), b.x, b.y)
        } ?? Cell(x: Int(point.x.rounded()), y: Int(point.y.rounded()))
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
