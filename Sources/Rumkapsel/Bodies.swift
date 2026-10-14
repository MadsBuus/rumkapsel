import Foundation

extension Simulation {
    func reconcileBodies() {
        for m in Array(bodies.values) where m.state != .leaving && m.wakeUntil == 0 && m.opacity > 0.5 {
            guard let c = m.current else { m.stallMark = ""; continue }
            let steady = (c.isRest && m.path.isEmpty) || m.lying || (m.path.isEmpty && clock < m.phaseUntil)
                || m.isQA || { if case .leave = c.kind { return true }; return false }()
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

    func giveUp(_ m: B, _ c: Command, why: String) {
        onEvent(.log("\(m.home.name) gives up \(c.words): \(why)"))
        switch c.kind {
        case .carry(let crate, let from, _):
            guard cargo[c.id] != nil else { finish(m); return }
            var spot = from
            if m.load == .crate(crate), let dropped = dropLoad(m) { spot = dropped }
            cargo[c.id]?.command = c.from(spot)
            cargo[c.id]?.carrier = nil
            cargo[c.id]?.hurry = false
            cargo[c.id]?.gaveUp.insert(m.id)
            m.current = nil; m.phase = 0; m.phaseUntil = 0; m.fetchSpot = nil
            finish(m)
        case .deliverOffice(let id):
            if m.hasLoad { dropLoad(m) }
            if world.truth.deliveries[id] != nil { world.truth.crateLanded(order: id); world.truth.fetchGivenUp(order: id, by: m.id) }
            finish(m)
        case .react:
            crewRested(m)
        default:
            if c.isRest {
                m.current = nil
                send(m, to: m.place)
            } else {
                m.seatedOnBowl = false
                m.fixture = nil
                m.drying = false
                finish(m)
            }
        }
    }

    func queueDeliveries() {
        for station in fleet.stations.values {
            for order in world.truth.deliveries.values where order.station == station.name && order.landed && station.rooms[order.roomKey] == nil {
                cue(.foldCrate(order.key))
                world.truth.officeDelivered(order.key)
                onEvent(.log("the office for \(order.roomKey) is gone: \(Words.current.foldsAway)"))
            }
            for key in world.truth.pendingOffices where key.hasPrefix(station.name + "|") && world.truth.delivery(for: key) == nil {
                let roomKey = String(key.dropFirst(station.name.count + 1))
                guard station.rooms[roomKey] != nil else { continue }
                orderDelivery(station: station, roomKey: roomKey, for: bodies.values.first { $0.station == station.name && $0.home.key == roomKey })
            }
        }
    }
}
