import Foundation
import simd

struct Hall {
    static let wide = 5, deep = 8
    static let padDeep = 3
    static let padRadius = 0.62
    static let none = Hall()

    let cells: [Cell]
    let walkwayCells: [Cell]
    let aisleCells: [Cell]
    let clearedCells: [Cell]
    let stagedCells: [Cell]
    let storageCells: [Cell]
    let clearedGrid: [[Cell]]
    let stagedGrid: [[Cell]]
    let storageGrid: [[Cell]]
    let padCells: [Cell]
    let deconCells: [Cell]
    let crateRows: Set<Cell>
    let windowWatch: [Cell]
    let padWall: [(hall: Cell, out: Cell)]
    let padField: (from: SIMD2<Double>, to: SIMD2<Double>)?
    let padCenter: SIMD2<Double>
    let padSlots: [SIMD2<Double>]
    let droneRackCell: Cell?
    let deconHatch: (pos: SIMD2<Double>, facing: SIMD2<Double>)

    var deckCells: [Cell] { clearedCells + stagedCells }

    private init() {
        cells = []; walkwayCells = []; aisleCells = []; clearedCells = []; stagedCells = []; storageCells = []
        clearedGrid = []; stagedGrid = []; storageGrid = []
        padCells = []; deconCells = []; crateRows = []; windowWatch = []; padWall = []; padField = nil
        padCenter = .zero; padSlots = []; droneRackCell = nil; deconHatch = (.zero, SIMD2(0, -1))
    }

    init(entrance: Cell, padGap: Int) {
        let x0 = entrance.x - 1, top = entrance.y - 6
        func row(_ y: Int) -> [Cell] { (1...4).map { Cell(x: x0 - 5 + $0, y: y) } }
        cells = (0..<Hall.deep).flatMap { d in (0..<Hall.wide).map { x in Cell(x: x0 - x, y: top + d) } }
        walkwayCells = (0..<Hall.deep).map { Cell(x: x0, y: top + $0) }
        aisleCells = row(top + 2) + row(top + 5)
        clearedGrid = [row(top), row(top + 1)]
        stagedGrid = [row(top + 3), row(top + 4)]
        storageGrid = [row(top + 6), row(top + 7)]
        clearedCells = clearedGrid.flatMap { $0 }
        stagedCells = stagedGrid.flatMap { $0 }
        storageCells = storageGrid.flatMap { $0 }
        deconCells = (0..<2).flatMap { d in (0..<Hall.wide).map { x in Cell(x: x0 - x, y: top + Hall.deep + d) } }
        crateRows = Set(storageCells + stagedCells + clearedCells + deconCells.filter { $0.y == top + Hall.deep + 1 })
        windowWatch = row(top + 2) + [Cell(x: x0, y: top), Cell(x: x0, y: top + 1)]
        padWall = (0..<Hall.wide).map { x in (Cell(x: x0 - x, y: top), Cell(x: x0 - x, y: top - 1)) }
        let z = Double(top) - 0.5
        padField = (SIMD2(Double(x0) - 4.5, z), SIMD2(Double(x0) + 0.5, z))
        let far = top - 1 - padGap
        var pad = (0..<Hall.padDeep).flatMap { r in (0..<Hall.wide).map { x in Cell(x: x0 - x, y: far - r) } }
        if padGap > 0 {
            for y in (far + 1)...(top - 1) { for x in [x0 - 1, x0] { pad.append(Cell(x: x, y: y)) } }
        }
        padCells = pad
        let center = SIMD2(Double(x0) - 2, Double(far) - 1)
        padCenter = center
        let along = Hall.padRadius * 3.squareRoot() + 0.08, across = along * 3.squareRoot() / 2
        padSlots = [(0.5, 0.5), (-0.5, 0.5), (0, -0.5), (1, -0.5), (-1, -0.5)].map { center + SIMD2($0.0 * along, $0.1 * across) }
        droneRackCell = Cell(x: x0, y: top - 1 - padGap)
        deconHatch = (SIMD2(Double(x0) - 2, Double(top + Hall.deep) + 1.46), SIMD2(0, -1))
    }

    func backRow(_ cell: Cell) -> (over: Cell, aisle: Cell)? {
        let floor = Set(aisleCells + walkwayCells)
        guard crateRows.contains(cell), !cell.neighbours.contains(where: floor.contains) else { return nil }
        for d in [Cell(x: 0, y: 1), Cell(x: 0, y: -1), Cell(x: 1, y: 0), Cell(x: -1, y: 0)] {
            let over = cell + d, aisle = over + d
            if crateRows.contains(over), floor.contains(aisle) { return (over, aisle) }
        }
        return nil
    }

    var deconDoorway: (hall: Cell, decon: Cell)? {
        walkwayCells.last.map { ($0, Cell(x: $0.x, y: $0.y + 1)) }
    }
}
