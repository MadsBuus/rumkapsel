// A station's floor, read from a baked plan rather than searched for.
//
// The old way found a place for each room by branch and bound over the whole floor, which cost a quarter
// of a second in one frame when a dozen offices arrived at once, and could only ever be as good as the
// search. The shapes of rooms do not depend on anything the station learns at run time, so the floor is
// drawn offline instead (floor/radial.py), checked there, and baked (floor/bake.py).
//
// A plan holds the quarters, the hallway lit before anything opens, and a hundred office slots in rings
// out from the monolith. Each slot carries the run of hallway that first reaches it, so lighting slots in
// order leaves the floor connected at every step — asserted here at load, not merely hoped for offline.
//
// The fixed floor is not in a plan. The yard, the airlock and the bay belong to the station and are the
// same whatever plan it uses; a plan was drawn around them, which is why a plan belongs to a theme — the
// pad stands somewhere else in Kenney, so the floor round it had to be drawn again.

import Foundation

struct Floorplan {
    struct Slot {
        let cells: [Cell]
        /// The hallway this slot lights with it. Empty when what is already lit reaches it.
        let hall: [Cell]
        /// Which ring out from the monolith this slot belongs to. Carried from the bake rather than
        /// worked out again here: the two languages round a half differently, and the order is the bake's.
        let ring: Int
    }

    let seed: Int
    /// The lounge, the dorm, the bath and the gym: placed by the plan, and lit from the start, since a
    /// station that cannot be slept in is not waiting on an office to arrive.
    let quarters: [String: [Cell]]
    /// Lit before a single office opens: the hallway that joins the plaza to the yard, the airlock and
    /// the quarters.
    let base: [Cell]
    let slots: [Slot]

    /// Every hallway cell the plan will ever have, lit or not. No room may stand on one, or the station
    /// would have to move a room the day a hallway reached it.
    let allHall: Set<Cell>
    /// Which slot a cell belongs to, so a room read back off disk can be matched to the slot it took.
    let slotOf: [Cell: Int]

    /// The plan a station of this name uses, in the theme the floor is laid out for. The same name gives
    /// the same floor on every machine, so two people sharing a station see the same one.
    static func forStation(_ name: String, theme: Theme = Theme.forPlan) -> Floorplan {
        let pool = all(theme)
        return pool[Int(stableHash(name) % UInt64(pool.count))]
    }

    private static var cached: [Theme: [Floorplan]] = [:]
    static func all(_ theme: Theme = Theme.forPlan) -> [Floorplan] {
        if let c = cached[theme] { return c }
        let plans = BakedPlans.forTheme(theme).map { parse($0) }
        cached[theme] = plans
        return plans
    }

    // MARK: reading the bake

    private static func cell(_ s: Substring) -> Cell {
        let p = s.split(separator: ",")
        return Cell(x: Int(p[0]) ?? 0, y: Int(p[1]) ?? 0)
    }
    private static func cells(_ s: Substring) -> [Cell] {
        s.isEmpty ? [] : s.split(separator: ";").map(cell)
    }

    private static func parse(_ text: String) -> Floorplan {
        var seed = 0
        var quarters: [String: [Cell]] = [:]
        var base: [Cell] = []
        var slots: [Slot] = []
        for line in text.split(separator: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)[...]
            guard let eq = line.firstIndex(of: "=") else { continue }
            let body = line[line.index(after: eq)...]
            switch line[..<eq] {
            case "seed": seed = Int(body) ?? 0
            case "base": base = cells(body)
            case "quarters":
                for part in body.split(separator: "|") {
                    guard let colon = part.firstIndex(of: ":") else { continue }
                    quarters[String(part[..<colon])] = cells(part[part.index(after: colon)...])
                }
            case "offices":
                for part in body.split(separator: "|") {
                    let f = part.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
                    slots.append(Slot(cells: cells(f[0]),
                                      hall: f.count > 1 ? cells(f[1]) : [],
                                      ring: f.count > 2 ? (Int(f[2]) ?? 0) : 0))
                }
            default: break
            }
        }
        var allHall = Set(base)
        var slotOf: [Cell: Int] = [:]
        for (i, s) in slots.enumerated() {
            allHall.formUnion(s.hall)
            for c in s.cells { slotOf[c] = i }
        }
        let plan = Floorplan(seed: seed, quarters: quarters, base: base, slots: slots,
                             allHall: allHall, slotOf: slotOf)
        plan.check()
        return plan
    }

    // MARK: what the bake promises

    /// Light the slots one at a time and hold the plan to what it claims: the floor is one piece at every
    /// step, every office opens with a door onto lit hallway, and no office stands on hallway or a block.
    /// Cheap enough to run at load — four plans, a hundred steps each — and it turns a bad bake into a
    /// crash at launch rather than a station that has a room nobody can walk to.
    func check() {
        var lit = Set(base)
        let rooms = Set(quarters.values.joined())
        precondition(!lit.isEmpty, "plan \(seed): nothing is lit before the offices")
        precondition(connected(lit, through: lit.union(rooms)), "plan \(seed): the base hallway is in pieces")
        for (name, cs) in quarters {
            precondition(cs.contains { c in c.neighbours.contains { lit.contains($0) } },
                         "plan \(seed): the \(name) has no way in before any office opens")
        }
        for (i, slot) in slots.enumerated() {
            lit.formUnion(slot.hall)
            precondition(connected(lit, through: lit.union(rooms)), "plan \(seed): the hallway broke at office \(i)")
            precondition(slot.cells.contains { c in c.neighbours.contains { lit.contains($0) } },
                         "plan \(seed): office \(i) opens with no door")
            precondition(!slot.cells.contains { lit.contains($0) || rooms.contains($0) },
                         "plan \(seed): office \(i) stands on hallway or the quarters")
        }
    }

    private func connected(_ want: Set<Cell>, through floor: Set<Cell>) -> Bool {
        guard let start = want.first else { return true }
        var seen: Set<Cell> = [start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let c = queue[head]; head += 1
            for n in c.neighbours where floor.contains(n) && !seen.contains(n) { seen.insert(n); queue.append(n) }
        }
        return want.isSubset(of: seen)
    }
}
