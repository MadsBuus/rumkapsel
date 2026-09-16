// The body reconciler: what the crate ledger is for crates, this is for minions.
//
// Every command in hand is either making progress, or waiting on a fact it has named. Anything else
// is a stall, and after ten station seconds the minion gives up: it says so in the log, puts down what
// it holds where it stands, and is free again. Nothing is lost by giving up, because the work is not
// kept in the minion: a carry goes back into the cargo queue from where the crate now lies, a new
// office's crate stays on the floor for whoever is free next, and a visit simply ends. The ordinary
// rules then re-issue whatever truth still wants, so a stranded job is retried rather than abandoned,
// and a job whose conditions went away is dropped without a body left standing somewhere.

import Foundation

extension Simulation {
    func reconcileBodies() {
        for m in Array(bodies.values) where m.state != .leaving && m.wakeUntil == 0 && m.opacity > 0.5 {
            guard let c = m.current else { m.stallMark = ""; continue }
            // Where it stands, what it holds, what phase it is in: the same for ten seconds is a stall.
            // Standing still is the whole point of a rest that has arrived, a lie-down or an act with time
            // left on it. A wait on a named fact is allowed its time, but not forever: a fact that has not
            // come in ninety station seconds is one that is not coming, and the wait is given up too.
            let steady = (c.isRest && m.path.isEmpty) || m.lying || (m.path.isEmpty && clock < m.phaseUntil)   // any timed phase: an act, a reaction, a crouch
                || m.isQA || { if case .leave = c.kind { return true }; if case .waitPallet = c.kind { return true }; return false }()   // walking the rows, the airlock's cycle, standing by a pallet for a release that may take hours: standing is the work
            if steady { m.stallMark = ""; continue }
            let s = Station.sub(m.pos)
            let mark = "\(c.id)|\(m.phase)|\(s.x),\(s.y)|\(m.path.count)|\(m.waitingOn ?? "")"
            if mark != m.stallMark { m.stallMark = mark; m.stallSince = clock; continue }
            let limit = m.waitingOn != nil ? Patience.waitLimit : Patience.giveUpAfter
            guard clock - m.stallSince > limit else { continue }
            m.stallMark = ""
            let blocked = m.blockedBy.flatMap { bodies[$0] }.map { b in
                ", \(b.home.name) in the way at \(b.cell.x),\(b.cell.y) \(b.waitingOn.map { "waiting on \($0)" } ?? (b.path.isEmpty ? "standing" : "walking"))"
            } ?? ""
            let why = m.waitingOn.map { "waited \(Int(limit)) s on \($0)" } ?? "stood \(Int(limit)) s at \(m.cell.x),\(m.cell.y) in \(m.phaseKind)\(blocked)"
            giveUp(m, c, why: why)
        }
        queueDeliveries()
    }

    /// The command goes back to truth and the minion is free: a carry is re-queued from where the
    /// crate now lies; a new office's crate waits on the floor for the next free hands; anything
    /// else just ends. Said in the log every time, so a repeat is a bug that shows rather than hides.
    func giveUp(_ m: B, _ c: Command, why: String) {
        onEvent(.log("\(m.home.name) gives up \(c.words): \(why)"))
        switch c.kind {
        case .carry(let crate, let from, _):
            guard cargo[c.id] != nil else { finish(m); return }
            var spot = from
            if m.load == .crate(crate) {
                dropLoad(m)   // the crate lies an arm's length behind, on the way it came: the next carrier reaches it without passing the body
                let behind = SIMD2(m.pos.x - sin(m.facing) * Hands.arm, m.pos.y - cos(m.facing) * Hands.arm)
                let cell = Cell(x: Int(behind.x.rounded()), y: Int(behind.y.rounded()))
                if let st = fleet.stations[m.station] {
                    spot = Spot(area: from.area, station: from.station, owner: from.owner, label: from.label, cell: cell,
                                pos: SIMD3(st.offset.x + behind.x, 0.12, st.offset.y + behind.y))
                }
            }
            cargo[c.id]?.command = c.from(spot)   // the same order, the same id: only where it starts moved
            cargo[c.id]?.carrier = nil
            cargo[c.id]?.hurry = false
            cargo[c.id]?.gaveUp.insert(m.id)   // somebody else's turn, while there is somebody else
            m.current = nil; m.phase = 0; m.phaseUntil = 0; m.fetchSpot = nil
            finish(m)
        case .deliverOffice(let id):
            // The crate stays on the floor, wherever that is, under its order: the queue hands it on.
            if m.hasLoad { dropLoad(m) }
            if world.truth.deliveries[id] != nil { world.truth.crateLanded(order: id); world.truth.fetchGivenUp(order: id, by: m.id) }
            finish(m)
        case .react:
            crewRested(m)   // a teammate's reaction ends the way it always ends: activity, tools and all
        default:
            if c.isRest {
                m.current = nil
                send(m, to: m.place)   // the same rest, planned afresh from here
            } else {
                m.seatedOnBowl = false
                m.fixture = nil
                m.drying = false
                finish(m)
            }
        }
    }

    /// New offices are a queue, not an errand tied to one body. A crate on the bay floor is a fact,
    /// and the station always acts on it: with nobody fetching it, it goes to the next free minion,
    /// the session it was ordered for first, whoever gave it up last. It goes into whatever room its
    /// order names now, and if that room is gone it folds away where it lies. A pending office with no
    /// order at all, no ship and nobody on it, has its shuttle ordered again.
    func queueDeliveries() {
        for station in fleet.stations.values {
            let fetching = Set(bodies.values.compactMap { m -> Int? in
                guard m.station == station.name, case .deliverOffice(let id) = m.current?.kind else { return nil }
                return id
            })
            let free = bodies.values.filter { $0.station == station.name && $0.isFree }
            for order in world.truth.deliveries.values where order.station == station.name && order.landed && !fetching.contains(order.id) {
                guard let room = station.rooms[order.roomKey] else {
                    // The office went away while its crate was on the floor: the crate folds away where it lies.
                    cue(.foldCrate(order.key))
                    world.truth.officeDelivered(order.key)
                    onEvent(.log("the office for \(order.roomKey) is gone: \(Words.current.foldsAway)"))
                    continue
                }
                let box = bayCrate(order, station: station).at
                func distance(_ a: B) -> Double { abs(a.pos.x - box.x) + abs(a.pos.y - box.y) }
                let fresh = free.filter { !order.gaveUp.contains($0.id) }
                let pool = fresh.isEmpty ? free : fresh
                guard let m = pool.first(where: { $0.id == order.session }) ?? pool.min(by: { distance($0) < distance($1) }) else { continue }
                start(m, .deliverOffice(order: order.id, name: room.name), announce: false)
                guard case .deliverOffice = m.current?.kind else { continue }
                m.couch = nil; m.bed = nil
                m.place = .hangar
                onEvent(.log("\(m.home.name) picks up the office for \(room.name) from \(Words.current.theBay)"))
            }
            // Pending with no order and no ship: the shuttle never came, or the app was relaunched under it.
            for key in world.truth.pendingOffices where key.hasPrefix(station.name + "|") && world.truth.delivery(for: key) == nil {
                let roomKey = String(key.dropFirst(station.name.count + 1))
                guard station.rooms[roomKey] != nil,
                      let m = free.first(where: { $0.home.key == roomKey }) ?? free.first else { continue }
                startDelivery(m, roomKey: roomKey)
            }
        }
    }
}
