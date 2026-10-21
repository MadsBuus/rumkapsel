import Foundation

struct Footprint {
    let at: SIMD2<Double>
    let radius: Double

    static func crate(_ at: SIMD2<Double>, _ zone: Zone = .waiting, failing: Bool = false, scale: Double = 1) -> Footprint {
        Footprint(at: at, radius: (failing ? 0.5312 : 0.52) * zone.crateSize * scale)
    }
    static func cube(_ c: Cube, failing: Bool, scale: Double) -> Footprint {
        Footprint(at: SIMD2(c.pos.x, c.pos.z), radius: (failing ? 0.532 : 0.5) * c.size * scale)
    }
    static func cone(_ c: Cell) -> Footprint { Footprint(at: SIMD2(Double(c.x), Double(c.y)), radius: Theme.forPlan.cone) }
    static func rocket(_ at: SIMD2<Double>) -> Footprint { Footprint(at: at, radius: 0.3) }

    var cells: [Cell] {
        let f = Double(Station.fine)
        let xs = Int(((at.x - radius) * f).rounded())...Int(((at.x + radius) * f).rounded())
        let ys = Int(((at.y - radius) * f).rounded())...Int(((at.y + radius) * f).rounded())
        return xs.flatMap { x in ys.map { Cell(x: x, y: $0) } }
    }
}

extension Theme {
    var cone: Double { self == .kingdom ? 0.1619 : 0.1472 }
}

extension Station {
    func furniture(_ theme: Theme, offices: [Room]) -> Set<Cell> {
        var out: Set<Cell> = []
        func place(_ room: Room?, _ prints: [Footprint]) {
            guard let room else { return }
            let floor = Set(room.cells)
            for p in prints { out.formUnion(p.cells.filter { floor.contains(Station.cell(ofSub: $0)) }) }
        }
        let o = offset, kingdom = theme == .kingdom
        if let lounge = rooms["kind:lounge"] {
            let s = loungeSpots(lounge: lounge)
            let seats = couches.map { Footprint(at: $0, radius: kingdom ? 0.2556 : 0.32) }
            let rest = kingdom
                ? [Footprint(at: s.table - o, radius: 0.2)] + loungeBarrels(lounge: lounge).map { Footprint(at: $0 - o, radius: 0.1603) }
                : [Footprint(at: s.table - o, radius: 0.36), Footprint(at: s.pot - o, radius: 0.1226), Footprint(at: s.shelf - o, radius: 0.28)]
            place(lounge, rest + seats)
        }
        if let bath = rooms["kind:bath"] {
            place(bath, [Footprint(at: bowlSpot(bath: bath) - o, radius: kingdom ? 0.0634 : 0.148), Footprint(at: showerArm(bath: bath) - o, radius: 0.1),
                         Footprint(at: showerPole(bath: bath) - o, radius: 0.034), Footprint(at: towelRail(bath: bath) - o, radius: 0.096)]
                + (kingdom ? [Footprint(at: showerNozzle(bath: bath) - o, radius: 0.208)] : []))
        }
        if let galley { place(rooms["kind:galley"], galley.counter.map { Footprint(at: $0, radius: Galley.counterWidth / 2 * 0.8) }) }
        for key in ["kind:mission"] {
            let fixtures = self.fixtures(in: key)
            let seats = fixtures.flatMap { f in f.kind.anchors.indices.compactMap { f.place($0) }.filter { $0.use != .stand } }
            place(rooms[key], fixtures.map { Footprint(at: $0.at, radius: max($0.kind.size.x, $0.kind.size.y) / 2 * 0.8) }
                + seats.map { Footprint(at: $0.at, radius: max(Seat.size.x, Seat.size.y) / 2 * 0.8) })
        }
        place(rooms["kind:quarters"], beds.map { Footprint(at: $0.pos, radius: $0.level > 0 ? 0.296 : kingdom ? 0.2066 : 0.288) })
        for room in offices {
            guard let at = desk(room, theme: theme) else { continue }
            place(room, [Footprint(at: at, radius: kingdom ? 0.178 : 0.168)])
        }
        return out
    }

    var doorPosts: Set<Cell> {
        Set(glassDoors.flatMap { [$0.at - SIMD2(0.5, 0), $0.at + SIMD2(0.5, 0)] }.map(Station.sub))
    }

    var glassDoors: [(at: SIMD2<Double>, facing: SIMD2<Double>, hatch: Bool)] {
        (bayDoor.map { [(SIMD2(Double($0.inside.x), Double($0.inside.y) + 0.5), SIMD2(0, 1), false)] } ?? [])
            + (hasPad ? [(hall.deconHatch.pos, hall.deconHatch.facing, true)] : [])
    }
}

extension Simulation {
    func refreshObstacles() {
        let live = Set(fleet.stations.values.flatMap { st in (shown[st.name]?.offices.keys).map { $0.map { st.name + "|" + $0 } } ?? [] })
        marked = marked.filter { live.contains($0.key) }
        for st in fleet.stations.values { st.obstacles = obstacles(st) }
    }

    func obstacles(_ st: Station) -> Set<Cell> {
        let o = st.offset
        var prints: [Footprint] = []
        for (_, at) in shown[st.name]?.crates ?? [:] {
            switch at {
            case .row(let s): prints.append(.crate(SIMD2(s.pos.x, s.pos.z) - o, s.zone))
            case .falling(let to, _, _): prints.append(.crate(SIMD2(to.pos.x, to.pos.z) - o, to.zone))
            case .office(let room):
                guard let cell = packageCell(st, room) ?? shown[st.name]?.offices[room]?.door else { continue }
                prints.append(.crate(SIMD2(Double(cell.x), Double(cell.y))))
            case .parked(let p):
                guard !st.hall.lanes.contains(p.cell) else { continue }
                prints.append(.crate(SIMD2(p.pos.x, p.pos.z) - o, Zone(area: p.area) ?? .waiting))
            case .hands, .vortex, .aboard: continue
            }
        }
        for (key, office) in shown[st.name]?.offices ?? [:] {
            guard let marks = marks(st, key) else { continue }
            let failing = office.look.failing
            var scale = 1.0
            if case .folding = office.phase { scale = office.label(at: clock) }
            guard scale >= 0.02 else { continue }
            if let cell = marks.package { prints.append(.crate(SIMD2(Double(cell.x), Double(cell.y)), failing: failing, scale: scale)) }
            prints += marks.pile.map { .cube($0, failing: failing, scale: scale) }
        }
        for m in bodies.values where m.station == st.name { prints += m.cones.map(Footprint.cone) }
        prints += shownRockets(st).compactMap { rocketSpot(st, $0.rocket).map(Footprint.rocket) }
        let offices = (shown[st.name]?.offices ?? [:]).filter { $0.value.up }.map { $0.value.room($0.key) }
        return Set(prints.flatMap(\.cells)).union(st.furniture(Theme.forPlan, offices: offices)).union(st.doorPosts)
    }
}
