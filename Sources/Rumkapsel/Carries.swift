// What a body does with a crate: a carry from where it stands to a yard, a new office's crate fetched
// from the bay, a cube stowed, a package packed. The simulation runs the phases and writes the ledger;
// the scene draws the crate on the arms while the body says it holds one, and puts it down where the
// body says it went. No SceneKit here.

import Foundation

/// How long a body may stand still before it gives up, and how long it may wait on a named fact.
enum Patience {
    /// Standing still, in the same phase, not waiting on anything named.
    static let giveUpAfter = 10.0
    /// Waiting on a fact the command named: a fact that has not come by then is one that is not coming.
    static let waitLimit = 90.0
}

extension Simulation {
    // MARK: the loads

    /// The load leaves the arms onto its slot: the ledger takes it, the scene lands the node there.
    func putDown(_ m: B, on spot: Spot) {
        m.load = nil
        m.settingDownOn = nil
        m.landing = Body.Landing(pos: spot.pos, yaw: spot.yaw)
    }

    /// A command whose target went away, or given up: put down what is on the arms, an arm's length
    /// behind where the body stands, on the way it came, never in the way ahead.
    func dropLoad(_ m: B) {
        guard m.hasLoad, let station = fleet.stations[m.station] else { return }
        let behind = SIMD3(station.offset.x + m.pos.x - sin(m.facing) * Hands.arm, 0.12, station.offset.y + m.pos.y - cos(m.facing) * Hands.arm)
        m.load = nil
        m.settingDownOn = nil
        m.landing = Body.Landing(pos: behind, yaw: nil, dropped: true)
        world.dropped(by: m.id)
    }

    /// Whatever was on the arms is simply gone: delivered by someone else, or the crate no more.
    func loseLoad(_ m: B) {
        m.load = nil
        m.settingDownOn = nil
        m.landing = nil
    }

    /// Standing over the slot: the level it goes onto decides the posture, the set-down the clock, and
    /// the scene draws the arc onto the spot from here.
    func startSetDown(_ m: B, on spot: Spot) {
        m.handsAt = spot.level
        m.settingDownOn = spot
        m.phaseUntil = clock + Hands.setDownSeconds
    }

    /// A body leaves the station: what it held goes down where it stands, and its carries wait for
    /// someone else.
    func forget(_ m: B) {
        if m.current?.crate != nil { dropLoad(m) }
        for (id, c) in cargo where c.carrier == m.id { cargo[id]?.carrier = nil }
        world.dropped(by: m.id)
        bodies[m.id] = nil
    }

    // MARK: carries

    /// Takes a carry command. The crate is spoken for from here on, so nothing else is told to move it
    /// and the yard layout leaves its spot alone. False when the yard has no place for it.
    @discardableResult
    func carry(_ command: Command, roomKey: String = "", onDone: @escaping () -> Void) -> Bool {
        guard let crate = command.crate, case .carry(_, _, let yard) = command.kind, let station = fleet.stations[crate.station] else { return false }
        world.claim(crate)
        station.ledger.order(repo: crate.repo, number: crate.number, to: yard)
        guard let aim = world.slotNow(for: crate, toward: yard) else { return false }
        cargo[command.id] = Cargo(command: command, onDone: onDone, carrier: nil, roomKey: roomKey, aim: aim)
        cue(.carryOrdered(id: command.id, crate: crate))
        return true
    }

    /// Drops every carry tied to a room, freeing whoever was carrying.
    /// Only carries into the office are dropped with it. A haul out of it, to storage, goes on: the
    /// crate belongs in storage whatever becomes of the office.
    func cancelCarries(roomKey: String) {
        for (id, c) in cargo where c.roomKey == roomKey {
            if case .carry(_, _, let to) = c.command.kind, to == .storage { continue }
            if let crate = c.command.crate { world.forgetPlacement(crate); world.unorder(crate) }
            cargo[id] = nil
            if let who = c.carrier, let m = bodies[who] { loseLoad(m); world.dropped(by: m.id); finish(m) }
        }
    }

    /// Gives waiting carries to free bodies on the same station.
    func scheduleCarries() {
        for (id, job) in cargo where job.carrier == nil {
            guard case .carry(let crate, let from, _) = job.command.kind, let station = fleet.stations[crate.station] else { continue }
            // Crates stacked above this one are still on their way: wait, deadline and all.
            guard job.command.after.allSatisfy({ cargo[$0] == nil }) else { continue }
            let all = bodies.values.filter { $0.station == crate.station && !$0.onJob && !$0.hasLoad && !$0.isSubagent && $0.state != .leaving && $0.wakeUntil == 0 }
            let fresh = all.filter { !job.gaveUp.contains($0.id) }
            let free = fresh.isEmpty ? all : fresh
            guard let m = free.min(by: { abs($0.cell.x - from.cell.x) + abs($0.cell.y - from.cell.y) < abs($1.cell.x - from.cell.x) + abs($1.cell.y - from.cell.y) }) else { continue }
            start(m, job.command, announce: true)
            guard m.current?.id == job.command.id else { continue }
            cargo[id]?.carrier = m.id
            m.bed = nil
            m.couch = nil   // off the couch: the seat is free for someone else
            m.path = route(m, to: standCell(station, near: from.cell))
        }
        // A carrier with carries of the same repository queued behind it picks up the pace, and says so once.
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

    /// The board put a crate back where it stands while a carry was under way: the order is off. On
    /// the arms already, it goes back to the slot it came from; not lifted yet, it simply stays.
    func cancelCarry(_ id: Int, backTo from: Spot) {
        guard let job = cargo[id], let crate = job.command.crate, let yard = Yard(area: from.area) else { return }
        if let who = job.carrier, let m = bodies[who], m.load == .crate(crate) {
            let back = job.command.aimed(at: yard)
            cargo[id]?.command = back
            cargo[id]?.aim = from
            world.unorder(crate)
            start(m, back)
            onEvent(.log("\(crate.words): back where it was, the board changed its mind"))
            return
        }
        if let who = job.carrier, let m = bodies[who], m.current?.id == id { finish(m) }
        world.forgetPlacement(crate)
        world.unorder(crate)
        cargo[id] = nil
        cue(.redraw)
        onEvent(.log("\(crate.words): stays put, the board changed its mind"))
    }

    // MARK: deliveries

    /// Where an office's crate is set down: just inside the doorway of the empty plot, by the hallway.
    /// The office unfolds from there.
    func officeCrateSlot(station: Station, roomKey: String) -> Spot? {
        guard let room = station.rooms[roomKey], let cell = station.doorCell(of: roomKey) ?? room.cells.first else { return nil }
        return Spot(area: .office, station: station.name, owner: roomKey, label: room.name, cell: cell,
                    pos: SIMD3(station.offset.x + Double(cell.x), 0.09, station.offset.y + Double(cell.y)))
    }

    /// Where a delivery's crate lies on the bay floor, in the station's own grid, and how high.
    func bayCrate(_ order: StationTruth.DeliveryOrder, station: Station) -> (at: SIMD2<Double>, height: Double) {
        (station.hangarSlots[min(order.slot, station.hangarSlots.count - 1)], 0.09)
    }

    /// The floor changed under a delivery: re-plan the walk to where it was going, the crate on the bay
    /// floor or the office's own slot, never somewhere at random.
    func replanDeliveries() {
        for m in bodies.values {
            guard case .deliverOffice(let id) = m.current?.kind, let station = fleet.stations[m.station], let order = world.truth.deliveries[id] else { continue }
            if !m.hasLoad {
                // Still waiting for the crate or its ship: the standing cell in front of the slot, never the slot.
                walk(m, to: station.bayStand(slot: order.slot))
            } else if let slot = officeCrateSlot(station: station, roomKey: order.roomKey) { walk(m, to: slot.cell) }   // on to the crate's own slot, not the door
        }
    }

    // MARK: the step

    /// One frame of a body with nowhere to walk and a crate to see to: a stow, a delivery, a pack, a
    /// carry. Nil when the command in hand is none of those.
    func stepCrate(_ m: B, station: Station, dt: Double) -> Outcome? {
        switch m.current?.kind {
        case .stow:
            // There: the cube comes off the head and goes down onto its place on the floor,
            // and the box drawn there takes over as it lands.
            if m.phaseKind == .walk {
                advance(m)
                m.phaseUntil = clock + 0.7
                cue(.stow(m.id))
                return .spent
            }
            if clock < m.phaseUntil { return .spent }
            finish(m)
            send(m, to: m.place)
            return .spent
        case .deliverOffice(let id):
            // Off the shuttle and into the office: the crate is fetched from the bay, lifted the
            // way any crate is lifted, and set down on the office's own slot before the reveal.
            // The order is the identity; the room it goes to is whatever the order says now.
            guard let order = world.truth.deliveries[id] else {
                // Delivered by someone else, or the office is gone: nothing to fetch.
                loseLoad(m)
                finish(m); return .spent
            }
            let r = order.roomKey
            let key = order.key
            let slot = officeCrateSlot(station: station, roomKey: r)
            switch m.phaseKind {
            case .walk:
                advance(m); return .spent
            case .approach:
                // Watching the crate come down, and the shuttle lift off it, before going over.
                if let spot = m.fetchSpot {
                    let d = spot - m.pos
                    if m.path.isEmpty, (d.x * d.x + d.y * d.y).squareRoot() > 0.05 { m.facing = atan2(d.x, d.y) }
                }
                if !order.landed { m.waitingOn = "the crate to come down"; return .spent }
                if shipStillOver(order: id, station: m.station) { m.waitingOn = Words.current.shipLeaving; return .spent }
                if m.fetchSpot != nil {
                    // Over to the standing cell in front of the crate; the last arm's length is taken from there,
                    // so the approach never comes from a neighbouring slot's side.
                    m.fetchSpot = nil
                    m.path = route(m, to: station.bayStand(slot: order.slot))
                    return .spent
                }
                guard m.path.isEmpty else { return .spent }
                // An arm's length from the crate, facing it, then the crouch: the same as any carry.
                let crate = bayCrate(order, station: station)
                guard atArmsLength(m, of: crate.at, dt: dt) else { return .spent }
                startLift(m, height: crate.height)
                advance(m); return .spent
            case .lift:
                guard liftDue(m) else { return .spent }
                if m.load == nil { m.load = .office(key) }
                if clock < m.phaseUntil { return .spent }
                advance(m)
                // The office went away while the crate was in the air: nothing to walk it into.
                // Carried to the corridor outside the doorway and set down just inside it.
                if let slot { walk(m, to: station.doorOutside(of: r) ?? slot.cell) } else { loseLoad(m); cue(.reveal(key)); finish(m) }
                return .spent
            case .haul:
                advance(m); return .spent
            default:
                guard let slot, m.hasLoad else {
                    loseLoad(m)
                    cue(.reveal(key))
                    finish(m)
                    return .spent
                }
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
                cue(.reveal(key))   // set down on its slot: the office fades in round it as the crate fades out
                finish(m)
                return .spent
            }
        case .pack(let office):
            // At the office's package slot: down on the knees over it for a moment, then the
            // crate is there, strapped, and the worker straightens up.
            if m.phaseKind == .walk {
                advance(m)
                m.phaseUntil = clock + 1.8
                return .spent
            }
            if clock < m.phaseUntil { return .spent }
            cue(.packed("\(m.station)|\(office)"))
            finish(m)
            send(m, to: m.place)
            return .spent
        case .carry(let crate, let from, _):
            guard let id = m.current?.id, let job = cargo[id] else {
                // The crate went away: put down whatever is on the arms, where it stands.
                dropLoad(m)
                finish(m); return .spent
            }
            let to = job.aim   // the place as it is now: asked again at lift, or sent back
            let boxAt = SIMD2(from.pos.x - station.offset.x, from.pos.z - station.offset.y)
            switch m.phaseKind {
            case .walk:
                advance(m); return .spent
            case .approach:
                // Stand an arm's length from the crate, facing it, before taking hold.
                guard atArmsLength(m, of: boxAt, dt: dt) else { return .spent }
                advance(m)
                startLift(m, height: from.pos.y)
                return .spent
            case .lift:
                // Take hold at the crate's own height, bring it up and over the head.
                let toBox = boxAt - m.pos
                if (toBox.x * toBox.x + toBox.y * toBox.y).squareRoot() > 0.05 { m.facing = atan2(toBox.x, toBox.y) }
                guard liftDue(m) else { return .spent }
                if m.load == nil {
                    m.load = .crate(crate)
                    world.pickedUp(crate, by: m.id)   // truth from the pickup: nobody else may move it
                }
                if clock < m.phaseUntil { return .spent }
                advance(m)
                // Up on the arms: now the slot is asked for, against the stack as it stands this moment.
                reaim(id)
                walk(m, to: standCell(station, near: (cargo[id]?.aim ?? to).cell))
                return .spent
            case .haul:
                advance(m); return .spent
            default:
                // Set the crate down squarely on its slot, then a beat before straightening up.
                // A crate is heavy: it stays on the arms all the way there and the hands do the lowering.
                let spot = SIMD2(to.pos.x - station.offset.x, to.pos.z - station.offset.y)
                if m.phaseUntil == 0 {
                    // A step back from the spot so the crate goes down in front, not underfoot.
                    guard atArmsLength(m, of: spot, dt: dt) else { return .spent }
                    startSetDown(m, on: to)
                    return .spent
                }
                let toSpot = spot - m.pos
                if (toSpot.x * toSpot.x + toSpot.y * toSpot.y).squareRoot() > 0.05 { m.facing = atan2(toSpot.x, toSpot.y) }
                if clock < m.phaseUntil { return .spent }
                putDown(m, on: to)
                cargo[id] = nil
                world.setDown(crate, at: to)
                cue(.landed(job))
                finish(m)
                return .spent
            }
        default:
            return nil
        }
    }
}
