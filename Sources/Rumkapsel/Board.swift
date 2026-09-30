// The station's order board. Everything the station wants done is an order on the board, not a
// command kept on a body, and whatever an order has got to is kept with the order (a carry's crate
// where it now lies, its aim), so whoever takes it next carries on from there.
//
// The board hands orders out on the reconciler's beat: the highest rank first, the oldest first within
// a rank, each to the nearest body allowed to take it. A body with nothing to do, or only resting, is
// free. A body on lower work is taken off it for higher work, at a safe point — walking or standing,
// never with something in its hands — and the order it was on goes back on the board to be picked up
// again, by it or by someone else. Work of the same rank never takes a body off another, so nobody
// flips between two. A body taken off its work stands a beat, head up, before it goes.
//
// Carries, the pallet's steps and welding a rocket's tip are on the board. Deliveries, packing, QA, the
// desk and the crew's reactions still run as a body's own commands; each is given its rank here so the
// board knows what it may take a body off, and none of them can be taken off yet.

import Foundation

/// How much a piece of work matters, lowest first.
enum Rank: Int, Comparable {
    /// Resting, a visit, a look round: whatever a body does when the board has nothing for it.
    case idle
    /// A teammate reacting to what they just did.
    case crew
    /// A session's body at its desk.
    case desk
    /// Walking the untested rows.
    case qa
    /// Keeping the yard: the pallet, carries to storage and decon, offices from the bay, packing.
    case yard
    /// Taking a release out: through the gate, onto the rocket, unloading once staging is live.
    case release
    /// A message from you to a session's body.
    case message
    /// Leaving the station, stepping out of the shuttle.
    case leaving

    static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }
}

/// An order on the board that nobody has: what the board needs to hand it out.
struct Opening {
    /// What the order is.
    let work: Work
    let rank: Rank
    let station: String
    /// Where the work starts, so it goes to the nearest body.
    let at: Cell
    /// When it went up, so the oldest of a rank goes first.
    let postedAt: Double
    /// Who gave it up: passed over for it while anyone else can take it.
    var gaveUp: Set<String> = []
    /// Only this body may take it: a teammate fetching their own new office.
    var only: String?
    /// This body takes it first when it is free: a session's own worker fetching its new office.
    var prefer: String?

    enum Work {
        /// A carry, by its command's id.
        case carry(Int)
        /// The next step a station's pallet is at, or ordering one.
        case pallet(station: String, step: PalletStep)
        /// Welding a repository's rocket tip.
        case weld(station: String, repo: String)
        /// Fetching a new office's crate from the bay, by its delivery order.
        case delivery(Int)
    }
}

/// A pallet's steps, each one an order: out at the console, loaded, pushed across, and unloaded onto the
/// deck, or back into storage when its release closed.
enum PalletStep {
    case order, load, push
    case unload(back: Bool)
}

extension Simulation {
    /// Every order nobody has, highest rank first, oldest first within a rank.
    func openings() -> [Opening] {
        var out: [Opening] = []
        for (id, job) in cargo where job.carrier == nil {
            guard case .carry(let crate, let from, _) = job.command.kind else { continue }
            // Crates stacked above this one are still on their way: it waits for them.
            guard job.command.after.allSatisfy({ cargo[$0] == nil }) else { continue }
            out.append(Opening(work: .carry(id), rank: rank(of: job.command), station: crate.station, at: from.cell,
                               postedAt: job.postedAt, gaveUp: job.gaveUp, prefer: job.prefer))
        }
        for order in world.truth.deliveries.values {
            guard let station = fleet.stations[order.station], station.rooms[order.roomKey] != nil,
                  !bodies.values.contains(where: { if case .deliverOffice(let id)? = $0.current?.kind { return id == order.id }; return false }) else { continue }
            let crew = order.session.flatMap { bodies[$0] }?.isCrew == true
            out.append(Opening(work: .delivery(order.id), rank: .yard, station: order.station, at: station.bayStand(slot: order.slot),
                               postedAt: Double(order.id), gaveUp: order.gaveUp, only: crew ? order.session : nil, prefer: crew ? nil : order.session))
        }
        for station in fleet.stations.values where station.hasPad && !station.storageCells.isEmpty {
            let name = station.name
            let onIt = { (match: (Command.Kind) -> Bool) in self.bodies.values.contains { $0.station == name && $0.current.map { match($0.kind) } ?? false } }
            if let p = pallets[name] {
                // Nobody holding it, or whoever was has gone on to something else.
                let held = p.hand.flatMap { bodies[$0] }.map { palletErrand(of: $0)?.station == name } ?? false
                if !held, let step = palletStep(p) {
                    let rank: Rank
                    if case .unload(back: false) = step { rank = .release } else { rank = .yard }
                    out.append(Opening(work: .pallet(station: name, step: step), rank: rank, station: name, at: p.cellUnder, postedAt: p.bornAt))
                }
            } else if world.truth.nextPallet(station: name) != nil,
                      !onIt({ if case .dispatch(let s, _, _) = $0 { return s == name }; return false }) {
                out.append(Opening(work: .pallet(station: name, step: .order), rank: .yard, station: name, at: station.storageConsole.cell, postedAt: 0))
            }
            for r in rockets.values where r.station == name && r.welding {
                guard !onIt({ if case .weld(let s, let repo, _) = $0 { return s == name && repo == r.repo }; return false }),
                      let at = rocketSpot(station: station, repo: r.repo) else { continue }
                out.append(Opening(work: .weld(station: name, repo: r.repo), rank: .release, station: name,
                                   at: Cell(x: Int(at.x.rounded()), y: Int(at.y.rounded())), postedAt: 0))
            }
        }
        return out.sorted { $0.rank != $1.rank ? $0.rank > $1.rank : $0.postedAt < $1.postedAt }
    }

    /// The step a pallet is at that wants hands, if any: nil while it waits on its own.
    func palletStep(_ p: PalletJob) -> PalletStep? {
        switch world.truth.pallets[p.station]?.state {
        case .loading?: return .load
        case .loaded?: return p.wantsBack ? .unload(back: true) : p.wantsPush ? .push : nil
        case .moving?: return .push
        case .staged?:
            // On the deck until what it carries is live on staging; a deploy that never shows is not waited for.
            let late = p.deploy == .unheard && clock - p.stagedAt > Deployments.findWithin
            return p.deploy == .live || late ? .unload(back: false) : nil
        case .unloading?: return .unload(back: p.wantsBack)
        default: return nil
        }
    }

    /// What a command is worth on the board.
    func rank(of c: Command) -> Rank {
        switch c.kind {
        case .carry(_, let from, let to):
            // Part of a release going out: into the rocket, off its stack, through the gate.
            let job = cargo[c.id]
            if to == .pad || from.area == .tested || from.area == .gate || job?.onBelt == true || job?.aim.area == .gate { return .release }
            return .yard
        case .unloadPallet(_, _, let back): return back ? .yard : .release
        case .weld: return .release
        case .deliverOffice, .pack, .stow, .dispatch, .loadPallet, .pushPallet: return .yard
        case .qa: return .qa
        case .work: return .desk
        case .react: return .crew
        case .leave: return .leaving
        case .goTo, .sleep, .bath, .exercise, .chore, .flight, .rocket: return .idle
        }
    }

    /// Whether the board can take a body off the command it is on, here and now, and put the command
    /// back: at a safe point, never mid-lift, mid-leg of a push, or with a crate in the air off the wand.
    private func releasable(_ m: B, _ c: Command) -> Bool {
        switch c.kind {
        case .carry: return cargo[c.id] != nil && m.phaseKind.interruptible
        case .dispatch: return m.phaseKind == .walk
        case .loadPallet(let s, _), .unloadPallet(let s, _, _): return m.phaseKind == .walk || pallets[s]?.flight == nil
        case .pushPallet(let s, _): return pallets[s]?.pushing == false
        case .weld: return true
        case .deliverOffice: return !m.hasLoad
        default: return false
        }
    }

    /// Whether a body may take orders from the board at all: not a teammate, a peer or a subagent,
    /// not the one walking the rows, not leaving, not still stepping out of the shuttle.
    private func onStaff(_ m: B) -> Bool {
        !m.isSubagent && !m.isCrew && !m.isPeer && !m.isQA && m.state != .leaving && m.wakeUntil == 0
    }

    /// Whether a body on lower work may be taken off it for work of `rank`: its order can go back on
    /// the board, ranks lower, and it is at a safe point, walking or standing with empty hands.
    private func canTakeOff(_ m: B, for rank: Rank) -> Bool {
        guard let c = m.current, self.rank(of: c) < rank else { return false }
        return !m.hasLoad && releasable(m, c)
    }

    /// A body just done with an order looks at the board before anything else: the best order it may
    /// take, if there is one, leaving alone any it gave up (the board's own pass hands one of those back
    /// only when nobody else can take it). False when there is nothing for it and it may go and rest.
    func takeNext(_ m: B) -> Bool {
        let mine = openings().filter { $0.station == m.station && !$0.gaveUp.contains(m.id) && ($0.only == m.id || ($0.only == nil && onStaff(m))) }
        // Kept for these hands first, then the rest by rank.
        for o in mine.filter({ $0.prefer == m.id }) + mine.filter({ $0.prefer != m.id }) where give(o, to: m) { return true }
        return false
    }

    /// Nothing in hand that ties it down: no job, nothing on the arms, and whatever it is doing may be cut
    /// into. The board's own word for free, which a teammate can be too, for an order of their own.
    private func free(_ m: B) -> Bool {
        !m.onJob && !m.hasLoad && m.state != .leaving && m.wakeUntil == 0 && (m.current == nil || m.phaseKind.interruptible)
    }

    /// Hands the board out: each order nobody has, highest first, to the nearest body allowed to take
    /// it — a free one if there is one, else one on lower work that can be taken off it.
    func assignOrders() {
        var taken = Set<String>()
        for o in openings() {
            // Allowed to take it: only the body it is kept for, or anyone on the staff.
            let staff = bodies.values.filter { $0.station == o.station && !taken.contains($0.id) && (o.only != nil ? $0.id == o.only : onStaff($0)) }
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

    /// The body's order goes back on the board as it stands, and the body stands a beat before the
    /// next thing.
    private func takeOff(_ m: B, for o: Opening) {
        guard let c = m.current else { return }
        switch c.kind {
        case .carry: cargo[c.id]?.carrier = nil
        case .loadPallet(let s, _), .pushPallet(let s, _), .unloadPallet(let s, _, _): pallets[s]?.hand = nil
        default: break
        }
        onEvent(.log("\(m.home.name) leaves \(c.words) for something more urgent"))
        m.current = nil; m.phase = 0; m.phaseUntil = 0; m.fetchSpot = nil; m.path = []
        m.wonderUntil = clock + 0.5
    }

    /// The order is the body's now, and it sets off. False when the body could not take it.
    private func give(_ o: Opening, to m: B) -> Bool {
        guard let station = fleet.stations[m.station] else { return false }
        switch o.work {
        case .carry(let id):
            guard let job = cargo[id], case .carry(_, let from, _) = job.command.kind else { return false }
            start(m, job.command, announce: true)
            guard m.current?.id == job.command.id else { return false }
            cargo[id]?.carrier = m.id
            // Off the belt from beside it; anything else from the floor beside the crate.
            if from.area == .gate, let belt = station.belt { walk(m, to: besideBelt(station, belt, at: from.pos)) }
            else { m.path = route(m, to: standCell(station, near: from.cell)) }
        case .pallet(_, .order):
            guard let want = world.truth.nextPallet(station: station.name) else { return false }
            start(m, .dispatch(station: station.name, repo: want.repo, number: want.number), announce: true)
            guard case .dispatch = m.current?.kind else { return false }
            m.place = .room("kind:storage")
            walk(m, to: station.storageConsole.cell)
        case .pallet(_, let step):
            guard let p = pallets[station.name] else { return false }
            switch step {
            case .load:
                start(m, .loadPallet(station: station.name, repo: p.repo), announce: true)
                guard case .loadPallet = m.current?.kind else { return false }
                p.hand = m.id
            case .push:
                guard m.current == nil || m.isFree else { return false }
                beginPush(m, station: station, p)
                return true
            case .unload(let back):
                guard m.current == nil || m.isFree else { return false }
                beginUnload(m, station: station, p, back: back)
            case .order:
                return false
            }
            m.place = .room(station.storageCells.contains(p.cellUnder) ? "kind:storage" : "kind:deck")
            m.path = []   // the step walks it up to the pallet from here, not wherever it was going
        case .delivery(let id):
            guard let order = world.truth.deliveries[id], let room = station.rooms[order.roomKey] else { return false }
            start(m, .deliverOffice(order: id, name: room.name), announce: false)
            guard case .deliverOffice = m.current?.kind else { return false }
            m.place = .hangar
            m.fetchSpot = station.hangarSlots[min(order.slot, station.hangarSlots.count - 1)]
            walk(m, to: station.bayStand(slot: order.slot))
            if order.landed { onEvent(.log("\(m.home.name) picks up the office for \(room.name) from \(Words.current.theBay)")) }
        case .weld(_, let repo):
            guard let side = weldSide(station: station, repo: repo) else { return false }
            start(m, .weld(station: station.name, repo: repo, side: side), announce: true)
            guard case .weld = m.current?.kind else { return false }
            m.path = []   // the weld walks it round to its side of the hull from here
        }
        m.bed = nil
        m.couch = nil   // off the couch: the seat is free for someone else
        return true
    }
}
