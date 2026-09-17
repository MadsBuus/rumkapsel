// The fixed skeleton every station shares: the plaza round the monolith, and the two arms that have to
// end where the yard and the airlock are. Nothing here is generated — a station's hallway and its rooms
// come from a baked floor plan (`Floorplan`), drawn offline around exactly these cells.

struct Plan {
    /// The middle tile of the plaza, where the monolith stands.
    let monolith = Cell(x: 0, y: 0)
    /// Three by three round the monolith, its tile included.
    let plaza: [Cell] = (-1...1).flatMap { x in (-1...1).map { y in Cell(x: x, y: y) } }
    /// The fixed arms, in order from the plaza: west ends at the deck's door, south at the airlock.
    let west: [Cell] = [Cell(x: -2, y: 0), Cell(x: -3, y: 0), Cell(x: -4, y: 0), Cell(x: -4, y: 1), Cell(x: -5, y: 1), Cell(x: -6, y: 1)]
    let south: [Cell] = [Cell(x: 0, y: 2), Cell(x: 0, y: 3), Cell(x: 1, y: 3), Cell(x: 1, y: 4), Cell(x: 1, y: 5)]
}

extension Cell {
    static func * (a: Cell, k: Int) -> Cell { Cell(x: a.x * k, y: a.y * k) }
}
