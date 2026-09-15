// The floor plan drawn from a station's name: a plaza round the monolith, four arms of hallway one tile
// wide, the two fixed ones short and straight enough to end at the yard and the bay, the two long ones
// wandering outward with alleys off them. A pure function of the seed, so every machine that has a
// station of the same name draws the same hallway, and a station never re-plans as it grows: the arms
// are drawn to a horizon at once and built outward as rooms need them.

import Foundation

struct Plan {
    /// The middle tile of the plaza, where the monolith stands.
    let monolith = Cell(x: 0, y: 0)
    /// Three by three round the monolith, its tile included.
    let plaza: [Cell] = (-1...1).flatMap { x in (-1...1).map { y in Cell(x: x, y: y) } }
    /// The fixed arms, in order from the plaza: west ends at the deck's door, south at the airlock.
    let west: [Cell] = [Cell(x: -2, y: 0), Cell(x: -3, y: 0), Cell(x: -4, y: 0), Cell(x: -4, y: 1), Cell(x: -5, y: 1), Cell(x: -6, y: 1)]
    let south: [Cell] = [Cell(x: 0, y: 2), Cell(x: 0, y: 3), Cell(x: 1, y: 3), Cell(x: 1, y: 4), Cell(x: 1, y: 5)]
    /// The long arms, in order from the plaza, drawn to the horizon.
    let north: [Cell]
    let east: [Cell]
    /// The alleys: each hangs off one arm at one step and runs one tile wide to a dead end.
    struct Alley {
        /// Which arm it hangs off, the arm cell it leaves from, and the built length at which it appears.
        let arm: Int; let base: Cell; let step: Int; let cells: [Cell]
        /// A shortcut: it runs on until it meets other hallway, so the way round is a loop, not a tree.
        var joins = false
    }
    let alleys: [Alley]
    /// How many steps the long arms are drawn: no room stands there, built or not.
    var horizon: Int { min(north.count, east.count) }
    /// Every hallway cell of the plan, built or not, plaza aside.
    let everyHallwayCell: Set<Cell>
    private let stepOf: [Cell: Int]

    init(seed: UInt64) {
        var rng = SplitMix(seed: seed)
        var taken = Set(plaza + west + south)
        // The long arms first: a run of two to four, a jog of one to the side, on again. The line drifts
        // no more than two tiles off its axis, and only one for the first two runs, so the arms leave the
        // plaza cleanly and never come near each other.
        func arm(from start: Cell, dir: Cell, side: Cell) -> [Cell] {
            var cells: [Cell] = []
            var p = start
            var lateral = 0
            for run in 0..<16 {
                let len = 2 + Int(rng.next() % 3)
                for _ in 0..<len { cells.append(p); p = p + dir }
                var s = rng.next() % 2 == 0 ? 1 : -1
                let bound = run < 2 ? 1 : 2
                if abs(lateral + s) > bound { s = -s }
                lateral += s
                let jog = cells.last! + side * s
                cells.append(jog)
                p = jog + dir
            }
            return cells
        }
        let north = arm(from: Cell(x: 0, y: -2), dir: Cell(x: 0, y: -1), side: Cell(x: 1, y: 0))
        let east = arm(from: Cell(x: 2, y: 0), dir: Cell(x: 1, y: 0), side: Cell(x: 0, y: 1))
        taken.formUnion(north); taken.formUnion(east)
        // Then the alleys: off every other run or so, two or three tiles, on the side away from the last
        // jog, and never within a tile of any other hallway, so a room fits on both sides of each.
        var alleys: [Alley] = []
        func clear(_ cells: [Cell], base: Cell, dir: Cell) -> Bool {
            for c in cells {
                for dx in -1...1 { for dy in -1...1 {
                    let n = Cell(x: c.x + dx, y: c.y + dy)
                    // The base and the arm's straight run through it are a tile away by nature; they do not count.
                    if cells.contains(n) || n == base || n == base + dir || n == base + (dir * -1) { continue }
                    if taken.contains(n) { return false }
                } }
            }
            return true
        }
        for (index, cells) in [north, east].enumerated() {
            let dir = index == 0 ? Cell(x: 0, y: -1) : Cell(x: 1, y: 0)
            let side = index == 0 ? Cell(x: 1, y: 0) : Cell(x: 0, y: 1)
            var sinceAlley = 0
            var i = 4   // the first run is the plaza's own approach; nothing hangs off it
            while i < cells.count - 1 {
                let here = cells[i], next = cells[i + 1]
                let straight = next == here + dir
                if straight, sinceAlley >= 4 {
                    // Off this cell, on the side the line last jogged away from.
                    let prevJog = (1...i).reversed().first { cells[$0] != cells[$0 - 1] + dir }.map { cells[$0].x - cells[$0 - 1].x + cells[$0].y - cells[$0 - 1].y } ?? 1
                    let preferred = -(prevJog == 0 ? 1 : prevJog.signum())
                    let len = 2 + Int(rng.next() % 2)
                    for s in [preferred, -preferred] {
                        let alley = (1...len).map { here + side * (s * $0) }
                        guard clear(alley, base: here, dir: dir) else { continue }
                        alleys.append(Alley(arm: index, base: here, step: i, cells: alley))
                        taken.formUnion(alley)
                        sinceAlley = 0
                        break
                    }
                }
                sinceAlley += 1
                i += 1
            }
        }
        var stepOf: [Cell: Int] = [:]
        for c in west + south { stepOf[c] = 0 }
        for (i, c) in north.enumerated() { stepOf[c] = i + 1 }
        for (i, c) in east.enumerated() { stepOf[c] = i + 1 }
        for a in alleys { for c in a.cells { stepOf[c] = a.step + 2 } }
        // Shortcuts: every other alley becomes a loop rather than a dead end. Out three tiles, along the
        // arm's own direction for four to six, and back in to meet the arm further on, so the way round
        // encloses a two-wide strip with room frontage on both sides, and the station is a web of ways
        // round rather than a tree. Never touching the yard or the bay, never brushing other hallway on
        // the way; a loop that cannot close stays the plain alley it was.
        let x0 = west.last!.x - 1, se = south.last!
        var avoid = Set<Cell>()
        for x in (x0 - 3)...x0 { for y in -5...8 { avoid.insert(Cell(x: x, y: y)) } }
        for y in (se.y + 1)...(se.y + 4) { for x in (se.x - 1)...(se.x + 1) { avoid.insert(Cell(x: x, y: y)) } }
        let armCells = [Set(north), Set(east)]
        for i in stride(from: 1, to: alleys.count, by: 2) {
            let a = alleys[i]
            let base = a.base
            let armDir = a.arm == 0 ? Cell(x: 0, y: -1) : Cell(x: 1, y: 0)
            let out = a.cells[0] + (base * -1)
            var cells = a.cells
            func free(_ p: Cell) -> Bool {
                guard !taken.contains(p), !avoid.contains(p) else { return false }
                let here = Set(cells)
                return !p.neighbours.contains { (taken.contains($0) && !here.contains($0) && $0 != base) || avoid.contains($0) }
            }
            var ok = true
            while cells.count < 3 { let c = cells.last! + out; guard free(c) else { ok = false; break }; cells.append(c) }
            guard ok else { continue }
            let along = 4 + Int(rng.next() % 3)
            var p = cells.last! + armDir
            for _ in 0..<along { guard free(p) else { ok = false; break }; cells.append(p); p = p + armDir }
            guard ok else { continue }
            var met: Cell?
            p = cells.last! + (out * -1)
            for _ in 0..<5 {
                guard !taken.contains(p), !avoid.contains(p) else { break }
                let here = Set(cells)
                let hits = p.neighbours.filter { taken.contains($0) && !here.contains($0) }
                cells.append(p)
                if let h = hits.first(where: { armCells[a.arm].contains($0) }) { met = h; break }
                if !hits.isEmpty { break }   // brushed something that is not the arm: no loop here
                p = p + (out * -1)
            }
            guard let met else { continue }
            let step = max(a.step, (stepOf[met] ?? 0) - 1)
            alleys[i] = Alley(arm: a.arm, base: base, step: step, cells: cells, joins: true)
            taken.formUnion(cells)
            for c in cells { stepOf[c] = step + 2 }
        }
        self.north = north; self.east = east; self.alleys = alleys
        var every = Set(west + south + north + east)
        for a in alleys { every.formUnion(a.cells) }
        self.everyHallwayCell = every
        self.stepOf = stepOf
    }

    /// The hallway built so far: the fixed arms whole, the long arms to `steps`, and the alleys whose
    /// base is built.
    func hallway(builtTo steps: Int) -> Set<Cell> {
        var out = Set(west + south)
        out.formUnion(north.prefix(steps)); out.formUnion(east.prefix(steps))
        for a in alleys where a.step + 1 < steps { out.formUnion(a.cells) }
        return out
    }

    /// At which built length a hallway cell appears: 0 for the plaza and the fixed arms.
    func revealStep(of c: Cell) -> Int { stepOf[c] ?? 0 }
}

/// A small deterministic generator: the same seed, the same numbers, on every machine.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension Cell {
    static func * (a: Cell, k: Int) -> Cell { Cell(x: a.x * k, y: a.y * k) }
}
