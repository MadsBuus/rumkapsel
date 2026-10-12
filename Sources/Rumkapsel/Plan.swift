struct Plan {
    let monolith = Cell(x: 0, y: 0)
    let plaza: [Cell] = (-1...1).flatMap { x in (-1...1).map { y in Cell(x: x, y: y) } }
    let west: [Cell] = [Cell(x: -2, y: 0), Cell(x: -3, y: 0), Cell(x: -4, y: 0), Cell(x: -4, y: 1), Cell(x: -5, y: 1), Cell(x: -6, y: 1)]
    let south: [Cell] = [Cell(x: 0, y: 2), Cell(x: 0, y: 3), Cell(x: 1, y: 3), Cell(x: 1, y: 4), Cell(x: 1, y: 5)]
}

extension Cell {
    static func * (a: Cell, k: Int) -> Cell { Cell(x: a.x * k, y: a.y * k) }
}
