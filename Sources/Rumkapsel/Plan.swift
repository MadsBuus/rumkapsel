// The skeleton of a station's floor plan, drawn from its name: a plaza round the monolith and four arms
// of hallway one tile wide, the two fixed ones short and straight enough to end at the yard and the bay,
// the two long ones wandering outward. A pure function of the seed, so every machine that has a station
// of the same name draws the same arms. The arms are drawn to a horizon at once and built outward as
// rooms need them; the alleys and the links between arms are not drawn here at all: the station digs
// them as rooms arrive, where they shorten the walk (`Station.placeShape`).

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
    /// How many steps the long arms are drawn: no room stands there, built or not.
    var horizon: Int { min(north.count, east.count) }
    /// Every hallway cell of the plan, built or not, plaza aside.
    let everyHallwayCell: Set<Cell>

    init(seed: UInt64) {
        var rng = SplitMix(seed: seed)
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
        self.north = north; self.east = east
        self.everyHallwayCell = Set(west + south + north + east)
    }
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
