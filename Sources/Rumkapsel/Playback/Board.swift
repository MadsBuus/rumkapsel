import Foundation

enum Rank: Int, Comparable {
    case idle
    case tidy
    case crew
    case desk
    case qa
    case yard
    case release
    case message
    case leaving

    static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }
}

struct Opening {
    let work: Work
    let rank: Rank
    let station: String
    let at: Cell
    let postedAt: Double
    var gaveUp: Set<String> = []
    var only: String?
    var prefer: String?
    var standby = false

    enum Work {
        case own(Int)
        case carry(Int)
        case delivery(Int)
        case qa(station: String)
    }
}

struct OwnOrder {
    let command: Command
    let body: String
    let rank: Rank
    let at: Cell
    let place: Place
    let postedAt: Double
    let announce: Bool
    var held = false
}

extension Simulation {
    func openings() -> [Opening] {
        var out: [Opening] = []
        for (id, o) in ownOrders where !o.held {
            guard let m = bodies[o.body] else { continue }
            if let turn = o.command.chore, ownOrders.contains(where: { other in
                guard other.key != id, other.value.body == o.body, let t = other.value.command.chore else { return false }
                return other.value.held || (t, other.value.postedAt, other.key) < (turn, o.postedAt, id)
            }) { continue }
            out.append(Opening(work: .own(id), rank: o.rank, station: m.station, at: o.at, postedAt: o.postedAt, only: o.body))
        }
        for (id, job) in cargo where job.carrier == nil {
            guard case .carry(let crate, let from, _) = job.command.kind else { continue }
            guard job.blockedBy.isEmpty else { continue }
            out.append(Opening(work: .carry(id), rank: rank(of: job.command), station: crate.station, at: from.cell,
                               postedAt: job.postedAt, gaveUp: job.gaveUp, prefer: job.prefer))
        }
        for order in deliveries {
            guard let station = fleet.stations[order.station], station.facts.offices[order.room] != nil, station.rooms[order.room] != nil,
                  !bodies.values.contains(where: { if case .deliverOffice(let id)? = $0.current?.kind { return id == order.id }; return false }) else { continue }
            let crew = order.who.flatMap { bodies[$0] }?.isCrew == true && clock - order.since < Delivery.patience
            out.append(Opening(work: .delivery(order.id), rank: .yard, station: order.station, at: station.bayStand(slot: order.slot),
                               postedAt: Double(order.id), gaveUp: order.gaveUp, only: crew ? order.who : nil, prefer: order.who))
        }
        for station in fleet.stations.values where qaWanted(station) {
            guard !bodies.values.contains(where: { $0.station == station.name && $0.isQA }), let at = station.hall.deckCells.first else { continue }
            out.append(Opening(work: .qa(station: station.name), rank: .qa, station: station.name, at: at, postedAt: 0, standby: true))
        }
        return out.sorted { $0.rank != $1.rank ? $0.rank > $1.rank : $0.postedAt < $1.postedAt }
    }

    func qaWanted(_ station: Station) -> Bool {
        guard !station.hall.deckCells.isEmpty, station.staged.values.reduce(0, +) > 0,
              !station.facts.rockets.values.contains(where: { $0.go && !$0.launched }) else { return false }
        return world.repoRoots.contains { _, info in
            guard info.station == station.name, world.workflow(repo: info.repo).has(.cleared) else { return false }
            let alien = Set(station.facts.crates.values.filter { $0.alien && $0.id.repo == info.repo }.map(\.id.number))
            return world.works.records(repo: info.repo).contains { r in r.stage == .qa && !(r.number.map(alien.contains) ?? false) }
        }
    }

    func rank(of c: Command) -> Rank {
        if let o = ownOrders[c.id] { return o.rank }
        switch c.kind {
        case .carry: return cargo[c.id]?.rank ?? .yard
        case .deliverOffice, .pack, .stow: return .yard
        case .qa: return .qa
        case .work: return .desk
        case .react: return .crew
        case .leave: return .leaving
        case .goTo, .sleep, .bath, .exercise, .galley, .watch, .chore, .flight: return .idle
        }
    }

    private func releasable(_ m: B, _ c: Command) -> Bool {
        switch c.kind {
        case .carry: return cargo[c.id] != nil && m.phaseKind.interruptible
        case .qa, .work, .react: return true
        case .bath, .exercise, .galley, .watch, .chore, .goTo, .sleep: return true
        case .deliverOffice: return !m.hasLoad
        default: return false
        }
    }

    private func onStaff(_ m: B) -> Bool {
        !m.isSubagent && !m.isCrew && !m.isPeer && m.state != .leaving && m.wakeUntil == 0
    }

    private func canTakeOff(_ m: B, for rank: Rank) -> Bool {
        guard let c = m.current, self.rank(of: c) < rank else { return false }
        return !m.hasLoad && releasable(m, c)
    }

    func takeNext(_ m: B) -> Bool {
        let mine = openings().filter { $0.station == m.station && !$0.gaveUp.contains(m.id) && ($0.only == m.id || ($0.only == nil && onStaff(m))) }
        for o in mine.filter({ $0.prefer == m.id }) + mine.filter({ $0.prefer != m.id }) where give(o, to: m) { return true }
        return false
    }

    private func free(_ m: B) -> Bool {
        !m.onJob && !m.hasLoad && m.wakeUntil == 0 && (m.current == nil || m.phaseKind.interruptible)
    }

    func assignOrders() {
        dropLostOrders()
        standDownQA()
        var taken = Set<String>()
        for o in openings() {
            let staff = bodies.values.filter { $0.station == o.station && !taken.contains($0.id) && (o.only != nil ? $0.id == o.only : onStaff($0))
                && (!o.standby || $0.freeSince > 0) }
            let idle = staff.filter { o.only != nil ? free($0) : $0.isFree }
            let pool = idle.isEmpty ? staff.filter { canTakeOff($0, for: o.rank) } : idle
            let fresh = pool.filter { !o.gaveUp.contains($0.id) }
            func distance(_ m: B) -> Int { abs(m.cell.x - o.at.x) + abs(m.cell.y - o.at.y) }
            let first = o.prefer.flatMap { p in pool.first { $0.id == p } }
            guard let m = first ?? (fresh.isEmpty ? pool : fresh).min(by: { distance($0) < distance($1) }) else { continue }
            if !idle.contains(where: { $0.id == m.id }) { takeOff(m, for: o) }
            if give(o, to: m) { taken.insert(m.id) }
        }
        hurryCarriers()
    }

    func post(_ c: Command, for m: B, rank: Rank, at: Cell, place: Place, announce: Bool = false) {
        for (id, o) in ownOrders where o.body == m.id && !o.held && o.command.kindName == c.kindName { drop(id) }
        ownOrders[c.id] = OwnOrder(command: c, body: m.id, rank: rank, at: at, place: place, postedAt: clock, announce: announce)
        assignOrders()
    }

    func dropOrders(at place: Place) {
        for (id, o) in ownOrders where o.place == place { drop(id) }
    }

    func moveOrders(from old: String, to new: String) {
        for (id, o) in ownOrders where o.place == .room(old) || o.command.office == old {
            let command = o.command.moved(from: old, to: new)
            let place = o.place == .room(old) ? Place.room(new) : o.place
            var moved = OwnOrder(command: command, body: o.body, rank: o.rank, at: o.at, place: place, postedAt: o.postedAt, announce: o.announce)
            moved.held = o.held
            ownOrders[id] = moved
            if let m = bodies[o.body], m.current?.id == id { m.current = command }
        }
    }

    private func drop(_ id: Int) {
        guard let o = ownOrders.removeValue(forKey: id) else { return }
        cue(.ownDropped(o.body, o.command))
    }

    private func dropLostOrders() {
        for (id, o) in ownOrders {
            let leaving: Bool = { if case .leave = o.command.kind { return true }; return false }()
            guard let m = bodies[o.body], m.state != .leaving || leaving else { drop(id); continue }
            if o.held, m.current?.id != id { drop(id) }
        }
    }

    private func standDownQA() {
        for m in bodies.values where m.isQA {
            guard let station = fleet.stations[m.station], !qaWanted(station) else { continue }
            m.busy = false
            m.activity = .waiting
            finish(m)
        }
    }

    private func takeOff(_ m: B, for o: Opening) {
        guard let c = m.current else { return }
        ownOrders[c.id]?.held = false
        dropLeftovers(m, of: c)
        switch c.kind {
        case .carry: cargo[c.id]?.carrier = nil
        case .qa: m.busy = false; m.activity = .waiting
        default: break
        }
        onEvent(.log("\(m.home.name) leaves \(c.words) for something more urgent"))
        m.current = nil; m.phase = 0; m.phaseUntil = 0; m.fetchSpot = nil; m.path = []
        m.wonderUntil = clock + 0.5
    }

    private func give(_ o: Opening, to m: B) -> Bool {
        guard let station = fleet.stations[m.station] else { return false }
        switch o.work {
        case .own(let id):
            guard let own = ownOrders[id] else { return false }
            if case .react = own.command.kind { if m.place != own.place || m.path.isEmpty { send(m, to: own.place) } }
            else { m.place = own.place }
            guard start(m, own.command, announce: own.announce) else { return false }
            ownOrders[id]?.held = true
            switch own.command.kind {
            case .react: break
            case .leave: walkOut(m)
            default: walk(m, to: own.at)
            }
            cue(.ownTaken(m.id, own.command))
        case .carry(let id):
            guard let job = cargo[id], case .carry(_, let from, _) = job.command.kind else { return false }
            start(m, job.command, announce: true)
            guard m.current?.id == job.command.id else { return false }
            cargo[id]?.carrier = m.id
            m.path = route(m, to: standCell(station, near: from.cell))
        case .delivery(let id):
            guard let order = delivery(id), let room = station.rooms[order.room] else { return false }
            start(m, .deliverOffice(order: id, name: room.name), announce: false)
            guard case .deliverOffice = m.current?.kind else { return false }
            m.place = .hangar
            m.fetchSpot = station.hangarSlots[min(order.slot, station.hangarSlots.count - 1)]
            walk(m, to: station.bayStand(slot: order.slot))
            if order.landed { onEvent(.log("\(m.home.name) picks up the office for \(room.name) from \(Words.current.theBay)")) }
        case .qa:
            m.activity = .qa
            m.busy = true
            send(m, to: .room("kind:deck"))
            start(m, .qa(deck: station.name))
            guard m.isQA else { return false }
            onEvent(.log("staging ready for QA · \(m.home.name) walks the rows"))
        }
        m.bed = nil
        m.couch = nil
        return true
    }
}
