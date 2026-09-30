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
// Carries are on the board. The pallet's errands, deliveries, packing, QA, the desk and the crew's
// reactions still run as a body's own commands; each is given its rank here so the board knows what it
// may take a body off, and none of them can be taken off yet.

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
    /// The order's own id: a carry's is its command's.
    let id: Int
    let rank: Rank
    let station: String
    /// Where the work starts, so it goes to the nearest body.
    let at: Cell
    /// When it went up, so the oldest of a rank goes first.
    let postedAt: Double
    /// Who gave it up: passed over for it while anyone else can take it.
    let gaveUp: Set<String>
}

extension Simulation {
    /// Every order nobody has, highest rank first, oldest first within a rank.
    func openings() -> [Opening] {
        var out: [Opening] = []
        for (id, job) in cargo where job.carrier == nil {
            guard case .carry(let crate, let from, _) = job.command.kind else { continue }
            // Crates stacked above this one are still on their way: it waits for them.
            guard job.command.after.allSatisfy({ cargo[$0] == nil }) else { continue }
            out.append(Opening(id: id, rank: rank(of: job.command), station: crate.station, at: from.cell,
                               postedAt: job.postedAt, gaveUp: job.gaveUp))
        }
        return out.sorted { $0.rank != $1.rank ? $0.rank > $1.rank : $0.postedAt < $1.postedAt }
    }

    /// What a command is worth on the board.
    func rank(of c: Command) -> Rank {
        switch c.kind {
        case .carry(_, let from, let to):
            // Part of a release going out: into the rocket, off its stack, through the gate.
            let job = cargo[c.id]
            if to == .pad || from.area == .tested || from.area == .gate || job?.onBelt == true || job?.aim.area == .gate { return .release }
            return .yard
        case .deliverOffice, .pack, .stow, .dispatch, .loadPallet, .waitPallet, .pushPallet, .unloadPallet: return .yard
        case .qa: return .qa
        case .work: return .desk
        case .react: return .crew
        case .leave: return .leaving
        case .goTo, .sleep, .bath, .exercise, .chore, .flight, .rocket: return .idle
        }
    }

    /// Whether the board can take a body off the command it is on and put the command back: only a
    /// carry, so far.
    private func releasable(_ c: Command) -> Bool {
        if case .carry = c.kind { return cargo[c.id] != nil }
        return false
    }

    /// Whether a body may take orders from the board at all: not a teammate, a peer or a subagent,
    /// not the one walking the rows, not leaving, not still stepping out of the shuttle.
    private func onStaff(_ m: B) -> Bool {
        !m.isSubagent && !m.isCrew && !m.isPeer && !m.isQA && m.state != .leaving && m.wakeUntil == 0
    }

    /// Whether a body on lower work may be taken off it for work of `rank`: its order can go back on
    /// the board, ranks lower, and it is at a safe point, walking or standing with empty hands.
    private func canTakeOff(_ m: B, for rank: Rank) -> Bool {
        guard let c = m.current, releasable(c), self.rank(of: c) < rank else { return false }
        return !m.hasLoad && m.phaseKind.interruptible
    }

    /// Hands the board out: each order nobody has, highest first, to the nearest body allowed to take
    /// it — a free one if there is one, else one on lower work that can be taken off it.
    func assignOrders() {
        var taken = Set<String>()
        for o in openings() {
            let staff = bodies.values.filter { $0.station == o.station && !taken.contains($0.id) && onStaff($0) }
            let free = staff.filter(\.isFree)
            let pool = free.isEmpty ? staff.filter { canTakeOff($0, for: o.rank) } : free
            let fresh = pool.filter { !o.gaveUp.contains($0.id) }
            func distance(_ m: B) -> Int { abs(m.cell.x - o.at.x) + abs(m.cell.y - o.at.y) }
            guard let m = (fresh.isEmpty ? pool : fresh).min(by: { distance($0) < distance($1) }) else { continue }
            if !m.isFree { takeOff(m, for: o) }
            if give(o, to: m) { taken.insert(m.id) }
        }
        hurryCarriers()
    }

    /// The body's order goes back on the board as it stands, and the body stands a beat before the
    /// next thing.
    private func takeOff(_ m: B, for o: Opening) {
        guard let c = m.current else { return }
        if case .carry = c.kind { cargo[c.id]?.carrier = nil }
        onEvent(.log("\(m.home.name) leaves \(c.words) for something more urgent"))
        m.current = nil; m.phase = 0; m.phaseUntil = 0; m.fetchSpot = nil; m.path = []
        m.wonderUntil = clock + 0.5
    }

    /// The order is the body's now, and it sets off. False when the body could not take it.
    private func give(_ o: Opening, to m: B) -> Bool {
        guard let job = cargo[o.id], case .carry(_, let from, _) = job.command.kind, let station = fleet.stations[m.station] else { return false }
        start(m, job.command, announce: true)
        guard m.current?.id == job.command.id else { return false }
        cargo[o.id]?.carrier = m.id
        m.bed = nil
        m.couch = nil   // off the couch: the seat is free for someone else
        m.path = route(m, to: standCell(station, near: from.cell))
        return true
    }
}
