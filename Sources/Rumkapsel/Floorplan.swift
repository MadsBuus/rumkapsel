// A station's floor, read from a baked plan rather than searched for.
//
// The old way found a place for each room by branch and bound over the whole floor, which cost a quarter
// of a second in one frame when a dozen offices arrived at once, and could only ever be as good as the
// search. The shapes of rooms do not depend on anything the station learns at run time, so the floor is
// drawn offline instead (floor/radial.py), checked there, and baked (floor/bake.py).
//
// A plan holds the fixed blocks, the hallway lit before anything opens, and a hundred office slots in
// radial order. Each slot carries the run of hallway that first reaches it, so lighting slots in order
// leaves the floor connected at every step — asserted here at load, not merely hoped for offline.

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
    let blocks: [String: [Cell]]
    /// Lit before a single office opens, so the deck, the bay and the quarters are joined from the start.
    let base: [Cell]
    let slots: [Slot]

    /// The plan a station of this name uses. The same name gives the same floor on every machine.
    static func forStation(_ name: String) -> Floorplan {
        all[Int(stableHash(name) % UInt64(all.count))]
    }

    static let all: [Floorplan] = BakedPlans.all.map { parse($0) }

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
        var blocks: [String: [Cell]] = [:]
        var base: [Cell] = []
        var slots: [Slot] = []
        for line in text.split(separator: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)[...]
            guard let eq = line.firstIndex(of: "=") else { continue }
            let body = line[line.index(after: eq)...]
            switch line[..<eq] {
            case "seed": seed = Int(body) ?? 0
            case "base": base = cells(body)
            case "fixed":
                for part in body.split(separator: "|") {
                    guard let colon = part.firstIndex(of: ":") else { continue }
                    blocks[String(part[..<colon])] = cells(part[part.index(after: colon)...])
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
        let plan = Floorplan(seed: seed, blocks: blocks, base: base, slots: slots)
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
        let blockCells = Set(blocks.values.joined())
        precondition(!lit.isEmpty, "plan \(seed): nothing is lit before the offices")
        precondition(connected(lit, through: lit.union(blockCells)), "plan \(seed): the base hallway is in pieces")
        for (name, cs) in blocks where name != "core" {
            precondition(cs.contains { c in c.neighbours.contains { lit.contains($0) } },
                         "plan \(seed): \(name) has no way in before any office opens")
        }
        for (i, slot) in slots.enumerated() {
            lit.formUnion(slot.hall)
            precondition(connected(lit, through: lit.union(blockCells)),
                         "plan \(seed): the hallway broke at office \(i)")
            precondition(slot.cells.contains { c in c.neighbours.contains { lit.contains($0) } },
                         "plan \(seed): office \(i) opens with no door")
            precondition(!slot.cells.contains { lit.contains($0) || blockCells.contains($0) },
                         "plan \(seed): office \(i) stands on hallway or a block")
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
