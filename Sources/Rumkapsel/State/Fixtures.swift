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

    func bathFixtures(bath: Room) -> (toilet: Cell, shower: Cell, toiletCorner: SIMD2<Double>, showerCorner: SIMD2<Double>) {
        let door = doorCell(of: bath.key)
        let maxY = bath.cells.map(\.y).max()!
        let sign = Cell(x: bath.cells.filter { $0.y == maxY }.map(\.x).max()!, y: maxY)
        var tiles = bath.cells.filter { $0 != door && $0 != sign }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        while tiles.count < 2, let more = bath.cells.first(where: { !tiles.contains($0) }) { tiles.append(more) }
        let mid = SIMD2(bath.cells.map { Double($0.x) }.reduce(0, +) / Double(bath.cells.count),
                        bath.cells.map { Double($0.y) }.reduce(0, +) / Double(bath.cells.count))
        func corner(_ c: Cell) -> SIMD2<Double> {
            let d = SIMD2(Double(c.x), Double(c.y)) - mid
            return SIMD2(d.x < 0 ? -1 : 1, d.y < 0 ? -1 : 1)
        }
        return (tiles[0], tiles[1], corner(tiles[0]), corner(tiles[1]))
    }

    func bowlSpot(bath: Room) -> SIMD2<Double> {
        let f = bathFixtures(bath: bath)
        return SIMD2(offset.x + Double(f.toilet.x) + 0.22 * f.toiletCorner.x, offset.y + Double(f.toilet.y) + 0.22 * f.toiletCorner.y)
    }

    func showerNozzle(bath: Room) -> SIMD2<Double> {
        let f = bathFixtures(bath: bath)
        return SIMD2(offset.x + Double(f.shower.x) + 0.3 * f.showerCorner.x, offset.y + Double(f.shower.y) + 0.25 * f.showerCorner.y)
    }

    func showerArm(bath: Room) -> SIMD2<Double> {
        let f = bathFixtures(bath: bath)
        return SIMD2(offset.x + Double(f.shower.x) + 0.3 * f.showerCorner.x, offset.y + Double(f.shower.y) + 0.35 * f.showerCorner.y)
    }

    func showerPole(bath: Room) -> SIMD2<Double> {
        let f = bathFixtures(bath: bath)
        return SIMD2(offset.x + Double(f.shower.x) + 0.3 * f.showerCorner.x, offset.y + Double(f.shower.y) + 0.45 * f.showerCorner.y)
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

    func desk(_ room: Room, theme: Theme) -> SIMD2<Double>? {
        guard theme != .classic, let wall = officeWall(room) else { return nil }
        let reach = theme == .kingdom ? 0.34 : 0.36
        return SIMD2(Double(wall.cell.x), Double(wall.cell.y)) + wall.out * reach
    }

    func towelRail(bath: Room) -> SIMD2<Double> {
        let f = bathFixtures(bath: bath)
        return SIMD2(offset.x + Double(f.shower.x) + 0.46 * f.showerCorner.x, offset.y + Double(f.shower.y) - 0.3 * f.showerCorner.y)
    }

    func towelStand(bath: Room) -> SIMD2<Double> {
        let f = bathFixtures(bath: bath)
        return SIMD2(offset.x + Double(f.shower.x) + 0.16 * f.showerCorner.x, offset.y + Double(f.shower.y) - 0.3 * f.showerCorner.y)
    }
}
