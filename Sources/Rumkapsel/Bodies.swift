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

extension StationController {
    /// How long a body may stand still, in the same phase, not waiting on anything named, before it gives up.
    static let giveUpAfter = 10.0

    func reconcileBodies() {
        for m in Array(minions.values) where m.state != .leaving && m.wakeUntil == 0 && m.opacity > 0.5 {
            guard let c = m.current else { m.stallMark = ""; continue }
            // Where it stands, what it holds, what phase it is in: the same for ten seconds is a stall.
            // Standing still is the whole point of a rest that has arrived, a lie-down or an act with time
            // left on it, and a wait on a named fact is not a stall while the fact is still to come.
            let steady = (c.isRest && m.path.isEmpty) || m.lying || (m.phaseKind == .act && clock < m.phaseUntil) || m.waitingOn != nil
                || m.isQA || { if case .leave = c.kind { return true }; return false }()   // walking the rows, or the airlock's cycle: standing is the work
            if steady { m.stallMark = ""; continue }
            let s = Station.sub(m.pos)
            let mark = "\(c.id)|\(m.phase)|\(s.x),\(s.y)|\(m.path.count)"
            if mark != m.stallMark { m.stallMark = mark; m.stallSince = clock; continue }
            guard clock - m.stallSince > StationController.giveUpAfter else { continue }
            m.stallMark = ""
            giveUp(m, c, why: "stood \(Int(StationController.giveUpAfter)) s at \(m.cell.x),\(m.cell.y) in \(m.phaseKind)")
        }
        queueDeliveries()
    }

    /// The command goes back to truth and the minion is free: a carry is re-queued from where the
    /// crate now lies; a new office's crate waits on the floor for the next free hands; anything
    /// else just ends. Said in the log every time, so a repeat is a bug that shows rather than hides.
    func giveUp(_ m: Minion, _ c: Command, why: String) {
        handle(.log("\(m.home.name) gives up \(c.words): \(why)"))
        switch c.kind {
        case .carry(_, let from, _):
            guard let job = cargo[c.id] else { finish(m); return }
            var spot = from
            if m.carried === job.node {
                dropWhereStanding(m)   // the crate lies an arm's length in front: the next carrier starts there
                let ahead = SIMD2(m.pos.x + sin(m.facing) * Hands.arm, m.pos.y + cos(m.facing) * Hands.arm)
                let cell = Cell(x: Int(ahead.x.rounded()), y: Int(ahead.y.rounded()))
                if let st = fleet.stations[m.station] {
                    spot = Spot(area: from.area, station: from.station, owner: from.owner, label: from.label, cell: cell,
                                pos: SIMD3(st.offset.x + ahead.x, 0.12, st.offset.y + ahead.y))
                }
            }
            cargo[c.id]?.command = c.from(spot)   // the same order, the same id: only where it starts moved
            cargo[c.id]?.carrier = nil
            cargo[c.id]?.issuedAt = clock
            cargo[c.id]?.hurry = false
            cargo[c.id]?.gaveUp.insert(m.id)   // somebody else's turn, while there is somebody else
            m.current = nil; m.phase = 0; m.phaseUntil = 0; m.fetchSpot = nil
            finish(m)
        case .deliverOffice(let r):
            let key = "\(m.station)|\(r)"
            if m.carried != nil { dropWhereStanding(m) }
            if boxes[key] != nil { world.truth.crateInBay(key) }   // on the floor, wherever that is: still to be fetched
            finish(m)
        default:
            if c.isRest {
                m.current = nil
                send(m, to: m.place)   // the same rest, planned afresh from here
            } else {
                m.setStatic(false, frame: 0)
                m.setBench(false)
                m.fixture = nil
                finish(m)
            }
        }
    }

    /// New offices are a queue, not an errand tied to one body: a crate on the bay floor with nobody
    /// fetching it goes to the next free minion, its own session's worker first. A pending office
    /// with no crate, no ship and nobody on it gets its shuttle ordered again.
    func queueDeliveries() {
        for station in fleet.stations.values {
            let fetching = Set(minions.values.compactMap { m -> String? in
                guard m.station == station.name, case .deliverOffice(let k) = m.current?.kind else { return nil }
                return k
            })
            let free = minions.values.filter { $0.station == station.name && !$0.onJob && $0.carried == nil && !$0.isSubagent && $0.state != .leaving && $0.wakeUntil == 0 && !$0.isCrew }
            for key in world.truth.pendingOffices where key.hasPrefix(station.name + "|") {
                let roomKey = String(key.dropFirst(station.name.count + 1))
                guard !fetching.contains(roomKey), let room = station.rooms[roomKey] else { continue }
                let inFlight = shuttles.contains { s in
                    guard s.station == station.name, case .flight(let kind, _, _) = s.command.kind, case .dropCrate(let k) = kind else { return false }
                    return k == roomKey
                }
                guard !inFlight else { continue }
                guard let m = free.first(where: { $0.home.key == roomKey }) ?? free.min(by: { a, b in
                    let box = boxes[key]?.worldPosition
                    let ax = box.map { abs(a.pos.x - (Double($0.x) - station.offset.x)) + abs(a.pos.y - (Double($0.z) - station.offset.y)) } ?? 0
                    let bx = box.map { abs(b.pos.x - (Double($0.x) - station.offset.x)) + abs(b.pos.y - (Double($0.z) - station.offset.y)) } ?? 0
                    return ax < bx
                }) else { continue }
                if boxes[key] != nil, world.truth.isInBay(key) {
                    // The crate is on the floor: fetch it from where it lies.
                    start(m, .deliverOffice(key: roomKey, name: room.name), announce: false)
                    guard case .deliverOffice = m.current?.kind else { continue }
                    m.couch = nil; m.bed = nil
                    m.place = .hangar
                    handle(.log("\(m.home.name) picks up the office for \(room.name) from the bay"))
                } else if boxes[key] == nil {
                    startDelivery(m, roomKey: roomKey)   // the ship never came, or came and went: order it again
                }
            }
        }
    }
}
