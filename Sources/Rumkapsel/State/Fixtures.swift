import Foundation

struct Galley {
    let cell: Cell
    let back: SIMD2<Double>

    var middle: SIMD2<Double> { SIMD2(Double(cell.x), Double(cell.y)) }
    var opening: SIMD2<Double> { middle - back * 0.5 }

    static let printSeconds = 10.0, slideSeconds = 0.5, pickSeconds = 0.8
}

extension Station {
    var galley: Galley? {
        guard let room = rooms["kind:galley"], let cell = room.cells.first, let out = doorOutside(of: room.key) else { return nil }
        return Galley(cell: cell, back: SIMD2(Double(cell.x - out.x), Double(cell.y - out.y)))
    }

    func loungeSpots(lounge: Room) -> (table: SIMD2<Double>, pot: SIMD2<Double>, shelf: SIMD2<Double>) {
        let xs = lounge.cells.map(\.x), ys = lounge.cells.map(\.y)
        let cx = Double(xs.reduce(0, +)) / Double(xs.count), cy = Double(ys.reduce(0, +)) / Double(ys.count)
        return (SIMD2(offset.x + cx, offset.y + cy),
                SIMD2(offset.x + Double(xs.min()!) + 0.3, offset.y + Double(ys.min()!) - 0.3),
                SIMD2(offset.x + Double(xs.max()!) - 0.3, offset.y + Double(ys.min()!) - 0.32))
    }

    func loungeBarrels(lounge: Room) -> [SIMD2<Double>] {
        let xs = lounge.cells.map(\.x), ys = lounge.cells.map(\.y)
        return [SIMD2(offset.x + Double(xs.min()!) - 0.28, offset.y + Double(ys.min()!) - 0.28),
                SIMD2(offset.x + Double(xs.max()!) + 0.1, offset.y + Double(ys.min()!) - 0.3)]
    }

    func officeWall(_ room: Room) -> (cell: Cell, out: SIMD2<Double>)? {
        let cells = Set(room.cells)
        guard let door = doorCell(of: room.key), let outside = doorOutside(of: room.key),
              let far = room.cells.max(by: { a, b in
                  (abs(a.x - door.x) + abs(a.y - door.y), -a.y, -a.x) < (abs(b.x - door.x) + abs(b.y - door.y), -b.y, -b.x)
              }) else { return nil }
        let sides = [Cell(x: far.x, y: far.y - 1), Cell(x: far.x, y: far.y + 1), Cell(x: far.x - 1, y: far.y), Cell(x: far.x + 1, y: far.y)]
        let walls = sides.filter { !cells.contains($0) && !($0 == outside && far == door) }
        guard let wall = walls.first(where: { self.room(at: $0) == nil && !isCorridor($0) }) ?? walls.first else { return nil }
        return (far, SIMD2(Double(wall.x - far.x), Double(wall.y - far.y)))
    }

    func isEpic(_ key: String) -> Bool { epics[key] != nil }

    func planningConsole(_ key: String) -> PlacedFixture? {
        guard isEpic(key), let room = rooms[key] ?? lingering[key], let wall = planningWall(room) else { return nil }
        let size = FixtureKind.planningConsole.size
        let at = SIMD2(Double(wall.cell.x), Double(wall.cell.y)) + wall.out * (0.5 - 0.04 - size.y / 2)
        return PlacedFixture(kind: .planningConsole, at: at, yaw: atan2(-wall.out.x, -wall.out.y))
    }

    func planningWall(_ room: Room) -> (cell: Cell, out: SIMD2<Double>)? {
        let cells = Set(room.cells)
        guard let door = doorCell(of: room.key), let outside = doorOutside(of: room.key), let top = room.cells.map(\.y).max(),
              let signX = room.cells.filter({ $0.y == top }).map(\.x).max() else { return nil }
        let skip: Set<Cell> = [door, Cell(x: signX, y: top)]
        func far(_ c: Cell) -> (Int, Int, Int) { (abs(c.x - door.x) + abs(c.y - door.y), -c.y, -c.x) }
        for roomy in [true, false] {
            for c in room.cells.filter({ !skip.contains($0) }).sorted(by: { far($0) > far($1) }) {
                let walls = [Cell(x: c.x, y: c.y - 1), Cell(x: c.x, y: c.y + 1), Cell(x: c.x - 1, y: c.y), Cell(x: c.x + 1, y: c.y)].filter { w in
                    let front = Cell(x: 2 * c.x - w.x, y: 2 * c.y - w.y)
                    return !cells.contains(w) && w != outside && (!roomy || cells.contains(front) && !skip.contains(front))
                }
                guard let wall = walls.first(where: { self.room(at: $0) == nil && !isCorridor($0) }) ?? walls.first else { continue }
                return (c, SIMD2(Double(wall.x - c.x), Double(wall.y - c.y)))
            }
        }
        return nil
    }

    func byTheDoor(_ room: Room) -> (at: SIMD2<Double>, inward: SIMD2<Double>, wall: SIMD2<Double>)? {
        guard let door = doorCell(of: room.key), let out = doorOutside(of: room.key) else { return nil }
        let cells = Set(room.cells)
        let e = SIMD2(Double(out.x - door.x), Double(out.y - door.y))
        let sides = [SIMD2(-e.y, e.x), SIMD2(e.y, -e.x)]
        func beyond(_ s: SIMD2<Double>) -> Cell { Cell(x: door.x + Int(s.x), y: door.y + Int(s.y)) }
        let side = sides.first { self.room(at: beyond($0)) == nil && !isCorridor(beyond($0)) } ?? sides.first { !cells.contains(beyond($0)) } ?? sides[0]
        return (SIMD2(Double(door.x), Double(door.y)) + side * 0.36 + e * 0.36, -e, side)
    }

    func consoleCells(_ key: String) -> Set<Cell> {
        guard let f = planningConsole(key) else { return [] }
        func cell(_ p: SIMD2<Double>) -> Cell { Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded())) }
        return Set([cell(f.at)] + (f.place(0).map { [cell($0.chair)] } ?? []))
    }

    func desk(_ room: Room, theme: Theme) -> SIMD2<Double>? {
        guard theme != .classic, !isEpic(room.key), let wall = officeWall(room) else { return nil }
        let reach = theme == .kingdom ? 0.34 : 0.36
        return SIMD2(Double(wall.cell.x), Double(wall.cell.y)) + wall.out * reach
    }
}
