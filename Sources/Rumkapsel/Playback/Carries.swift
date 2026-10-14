import Foundation
import simd

enum Patience {
    static let giveUpAfter = 10.0
    static let waitLimit = 90.0
    static let hallwayKept = 6.0
}

extension Simulation {
    // MARK: the loads

    func putDown(_ m: B, on spot: Spot) {
        m.load = nil
        m.settingDownOn = nil
        m.landing = Body.Landing(pos: spot.pos, yaw: spot.yaw)
    }

    @discardableResult
    func dropLoad(_ m: B) -> Spot? {
        guard m.hasLoad, let station = fleet.stations[m.station] else { return nil }
        let at = dropPoint(m, station: station)
        let behind = SIMD3(station.offset.x + at.x, 0.12, station.offset.y + at.y)
        let load = m.load
        m.load = nil
        m.settingDownOn = nil
        m.landing = Body.Landing(pos: behind, yaw: nil, dropped: true)
        guard case .crate(let crate)? = load else { return nil }
        var area = Spot.Area.storage
        if let job = m.current.flatMap({ cargo[$0.id] }), case .carry(_, let from, _) = job.command.kind { area = from.area }
        let spot = Spot(area: area, station: station.name, owner: crate.repo, label: crate.repo,
                        cell: Cell(x: Int(at.x.rounded()), y: Int(at.y.rounded())), pos: behind)
        shown[station.name]?.crates[CrateID(repo: crate.repo, number: crate.number)] = .parked(spot)
        cue(.redraw)
        return spot
    }

    func dropPoint(_ m: B, station: Station) -> SIMD2<Double> {
        let behind = SIMD2(m.pos.x - sin(m.facing) * Hands.arm, m.pos.y - cos(m.facing) * Hands.arm)
        let cell = Cell(x: Int(behind.x.rounded()), y: Int(behind.y.rounded()))
        guard !station.walkable.contains(cell), let floor = station.nearestFloor(to: behind) else { return behind }
        return SIMD2(Double(floor.x), Double(floor.y))
    }

    func loseLoad(_ m: B) {
        m.load = nil
        m.settingDownOn = nil
        m.landing = nil
    }

    func startSetDown(_ m: B, on spot: Spot, far: Bool = false) {
        m.floating = far
        m.handsAt = far ? 2 : spot.level
        m.settingDownOn = spot
        m.phaseUntil = clock + (far ? Hands.tossSeconds : Hands.setDownSeconds)
    }

    func forget(_ m: B) {
        abandon(m)
        let dropped = m.current?.crate != nil ? dropLoad(m) : nil
        for (id, c) in cargo where c.carrier == m.id {
            cargo[id]?.carrier = nil
            if let dropped { cargo[id]?.command = c.command.from(dropped) }
        }
        bodies[m.id] = nil
    }

    // MARK: carries

    func hurryCarriers() {
        for (id, job) in cargo where job.carrier != nil && !job.hurry {
            guard let crate = job.command.crate, case .carry(_, _, let to) = job.command.kind, let m = job.carrier.flatMap({ bodies[$0] }) else { continue }
            let queued = cargo.values.filter { $0.carrier == nil && $0.command.crate?.station == crate.station && $0.command.crate?.repo == crate.repo }.count
            guard queued > 0 else { continue }
            cargo[id]?.hurry = true
            let words = "hurrying \(crate.words) to \(to.words), \(queued) more waiting"
            if m.current?.id == id { m.current = m.current?.reworded(words) }
            onEvent(.log("\(m.home.name): \(words)"))
        }
    }

    // MARK: deliveries

    func officeCrateSlot(station: Station, roomKey: String) -> Spot? {
        guard let room = station.rooms[roomKey], let cell = station.doorCell(of: roomKey) ?? room.cells.first else { return nil }
        return Spot(area: .office, station: station.name, owner: roomKey, label: room.name, cell: cell,
                    pos: SIMD3(station.offset.x + Double(cell.x), 0.09, station.offset.y + Double(cell.y)))
    }

    func bayCrate(_ order: Delivery, station: Station) -> (at: SIMD2<Double>, height: Double) {
        (station.hangarSlots[min(order.slot, station.hangarSlots.count - 1)], 0.09)
    }

    func replanDeliveries() {
        for m in bodies.values {
            guard case .deliverOffice(let id) = m.current?.kind, let station = fleet.stations[m.station], let order = delivery(id) else { continue }
            if !m.hasLoad {
                walk(m, to: station.bayStand(slot: order.slot))
            } else if let slot = officeCrateSlot(station: station, roomKey: order.room) { walk(m, to: slot.cell) }
        }
    }

    // MARK: the step

    func stepCrate(_ m: B, station: Station, dt: Double) -> Outcome? {
        switch m.current?.kind {
        case .stow:
            if m.phaseKind == .walk {
                advance(m)
                m.phaseUntil = clock + 0.7
                cue(.stow(m.id))
                return .spent
            }
            if clock < m.phaseUntil { return .spent }
            if let id = m.current?.id { ownOrders[id] = nil }
            if case .stow(let office)? = m.current?.kind { stowed(station, office) }
            finish(m)
            send(m, to: m.place)
            return .spent
        case .deliverOffice(let id):
            guard let order = delivery(id) else {
                loseLoad(m)
                finish(m); return .spent
            }
            let r = order.room
            let slot = officeCrateSlot(station: station, roomKey: r)
            switch m.phaseKind {
            case .walk:
                advance(m); return .spent
            case .approach:
                if let spot = m.fetchSpot {
                    let d = spot - m.pos
                    if m.path.isEmpty, (d.x * d.x + d.y * d.y).squareRoot() > 0.05 { m.facing = atan2(d.x, d.y) }
                }
                if !order.landed { m.waitingOn = "the crate to come down"; return .spent }
                if shipStillOver(order: id, station: m.station) { m.waitingOn = Words.current.shipLeaving; return .spent }
                if m.fetchSpot != nil {
                    m.fetchSpot = nil
                    m.path = route(m, to: station.bayStand(slot: order.slot))
                    return .spent
                }
                guard m.path.isEmpty else { return .spent }
                let crate = bayCrate(order, station: station)
                guard atArmsLength(m, of: crate.at, dt: dt) else { return .spent }
                startLift(m, height: crate.height)
                advance(m); return .spent
            case .lift:
                guard liftDue(m) else { return .spent }
                if m.load == nil { m.load = .office(id) }
                if clock < m.phaseUntil { return .spent }
                guard let slot else { return .spent }
                advance(m)
                walk(m, to: station.doorOutside(of: r) ?? slot.cell)
                return .spent
            case .haul:
                advance(m); return .spent
            default:
                guard let slot else { return .spent }
                guard m.hasLoad else { finish(m); return .spent }
                let spot = SIMD2(slot.pos.x - station.offset.x, slot.pos.z - station.offset.y)
                if m.phaseUntil == 0 {
                    guard atArmsLength(m, of: spot, dt: dt) else { return .spent }
                    startSetDown(m, on: slot)
                    return .spent
                }
                let toSpot = spot - m.pos
                if (toSpot.x * toSpot.x + toSpot.y * toSpot.y).squareRoot() > 0.05 { m.facing = atan2(toSpot.x, toSpot.y) }
                if clock < m.phaseUntil { return .spent }
                putDown(m, on: slot)
                unfold(id)
                finish(m)
                return .spent
            }
        case .pack(let office):
            if m.phaseKind == .walk {
                advance(m)
                m.phaseUntil = clock + 1.8
                return .spent
            }
            if clock < m.phaseUntil { return .spent }
            if let id = m.current?.id { ownOrders[id] = nil }
            packed(station, office)
            finish(m)
            send(m, to: m.place)
            return .spent
        case .carry(let crate, let from, _):
            guard let id = m.current?.id, let job = cargo[id] else {
                dropLoad(m)
                finish(m); return .spent
            }
            let to = job.aim
            let boxAt = SIMD2(from.pos.x - station.offset.x, from.pos.z - station.offset.y)
            switch m.phaseKind {
            case .walk:
                advance(m); return .spent
            case .approach:
                if !job.blockedBy.isEmpty { m.waitingOn = Words.current.cratesOnTop; return .spent }
                guard atArmsLength(m, of: boxAt, dt: dt) else { return .spent }
                advance(m)
                startLift(m, height: from.pos.y, far: tossFrom(station, to: from.cell) != nil)
                return .spent
            case .lift:
                let toBox = boxAt - m.pos
                if (toBox.x * toBox.x + toBox.y * toBox.y).squareRoot() > 0.05 { m.facing = atan2(toBox.x, toBox.y) }
                guard liftDue(m) else { return .spent }
                if m.load == nil {
                    guard stillAt(job, from) else {
                        cargo[id] = nil
                        finish(m)
                        return .spent
                    }
                    m.load = .crate(crate)
                    shown[station.name]?.crates[job.crate] = .hands(m.id)
                    settle(station.name)
                    cue(.redraw)
                }
                if clock < m.phaseUntil { return .spent }
                advance(m)
                walk(m, to: standCell(station, near: (cargo[id]?.aim ?? to).cell))
                return .spent
            case .haul:
                advance(m); return .spent
            default:
                let spot = SIMD2(to.pos.x - station.offset.x, to.pos.z - station.offset.y)
                if m.phaseUntil == 0 {
                    if !job.blockedBy.isEmpty { m.waitingOn = Words.current.roomOnTheRow; return .spent }
                    guard atArmsLength(m, of: spot, dt: dt) else { return .spent }
                    startSetDown(m, on: to, far: tossFrom(station, to: to.cell) != nil)
                    return .spent
                }
                let toSpot = spot - m.pos
                if (toSpot.x * toSpot.x + toSpot.y * toSpot.y).squareRoot() > 0.05 { m.facing = atan2(toSpot.x, toSpot.y) }
                if clock < m.phaseUntil { return .spent }
                let on = m.settingDownOn ?? to
                putDown(m, on: on)
                let row = job.spot.flatMap { simd_distance($0.pos, on.pos) < 0.3 ? $0 : nil }
                shown[station.name]?.crates[job.crate] = row.map { .row($0) } ?? .parked(on)
                settle(station.name)
                cargo[id] = nil
                cue(.redraw)
                finish(m)
                return .spent
            }
        default:
            return nil
        }
    }
}
