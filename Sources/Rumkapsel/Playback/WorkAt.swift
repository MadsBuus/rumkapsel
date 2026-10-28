import simd
import Foundation

extension Simulation {
    func freeAnchors(_ m: B, station: Station, in room: String) -> [FixtureRef] {
        let taken = Set(bodies.values.filter { $0.id != m.id && $0.station == m.station }.compactMap(\.using))
        return station.anchors(in: room).filter { !taken.contains($0) }
    }

    static var atTheConsole: Double { 24 * 3600 }

    func console(of m: B, station: Station) -> FixtureRef? {
        guard !m.isSubagent, !m.isPeer, m.state != .leaving, m.activity != .waiting, station.facts.offices[m.home.key] != nil, station.epics[m.home.key]?.closed == false,
              station.planningConsole(m.home.key) != nil else { return nil }
        let ref = FixtureRef(room: m.home.key, fixture: 0, anchor: 0)
        return m.using == ref || freeAnchors(m, station: station, in: m.home.key).contains(ref) ? ref : nil
    }

    func leaveConsole(_ m: B, station: Station) {
        guard case .use(let ref, .planningConsole, _, _)? = m.current?.kind,
              console(of: m, station: station) != ref || restPlace(m) != .room(m.home.key) else { return }
        guard m.inPlace else { return finish(m, to: restPlace(m)) }
        let t = clock - m.actStartedAt, rise = 2 * Seat.swivel + Seat.sitDown
        if m.actFor - t > rise { m.actFor = t + rise; m.phaseUntil = m.actStartedAt + m.actFor }
    }

    @discardableResult
    func use(_ m: B, _ ref: FixtureRef, station: Station, seconds: Double, back: Place? = nil) -> Bool {
        guard let place = station.place(ref), let kind = station.fixtures(in: ref.room)[safe: ref.fixture]?.kind,
              let room = station.rooms[ref.room] else { return false }
        let back = back ?? m.place
        guard start(m, .use(ref, kind: kind, back: back, seconds: seconds), announce: true), m.using == ref else { return false }
        m.couch = nil
        m.place = .room(ref.room)
        let last: SIMD2<Double>
        switch place.use {
        case .stand: last = place.at + place.outward * Hands.arm
        case .spot: last = place.at
        case .sit, .lie: last = place.stand
        }
        m.path = route(m, to: standCell(station, near: last, within: Set(room.cells))) + [last]
        return true
    }

    func stepUse(_ m: B, station: Station, dt: Double) -> Bool {
        guard let ref = m.using, let order = m.current?.id, m.path.isEmpty, m.phaseKind == .act, let place = station.place(ref) else { return false }
        if !m.inPlace {
            if place.use == .stand, !atArmsLength(m, of: place.at, from: place.outward, square: true, dt: dt) { return true }
            if place.use == .spot { m.pos = place.at; m.facing = place.facing }
            m.settledOn = (order, nil, false)
            m.actStartedAt = clock
            m.phaseUntil = clock + m.actFor
        }
        if case .sit(let height) = place.use {
            let s = place.sitting(clock - m.actStartedAt, of: m.actFor)
            m.pos = s.pos
            m.facing = s.facing
            m.settledOn = (order, s.down ? height : nil, s.home)
        }
        guard clock >= m.phaseUntil else { return false }
        if m.isCrew, m.busy, case .use(_, .planningConsole, _, _)? = m.current?.kind {
            m.busy = false
            m.activity = .sleeping
            m.pyramidCell = nil
            cue(.clearCones(m.id))
        }
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
