import Foundation

struct Galley {
    let cell: Cell
    let back: SIMD2<Double>

    var middle: SIMD2<Double> { SIMD2(Double(cell.x), Double(cell.y)) }
    var across: SIMD2<Double> { SIMD2(back.y, -back.x) }
    var facing: Double { atan2(back.x, back.y) }
    var opening: SIMD2<Double> { middle - back * 0.5 }

    static let counterWidth = 0.32, counterDepth = 0.26, counterHeight = 0.26, nudge = 0.2
    static let printSeconds = 10.0, slideSeconds = 0.5, pickSeconds = 0.8

    func stand(_ fare: Command.Fare) -> SIMD2<Double> { middle + across * (fare == .coffee ? -Galley.nudge : Galley.nudge) }
    func machine(_ fare: Command.Fare) -> SIMD2<Double> { stand(fare) + back * Hands.arm }
    var counter: [SIMD2<Double>] { [-Galley.counterWidth, 0, Galley.counterWidth].map { middle + back * (0.5 - Galley.counterDepth / 2) + across * $0 } }
}

struct MissionControl {
    let x0: Int, y0: Int

    struct Spot { let at: SIMD2<Double>; let facing: Double; let seated: Bool }
    struct Console { let at: SIMD2<Double>; let yaw: Double }

    static let consoleDepth = 0.3, consoleWidth = 0.86, tableRadius = 0.5, holoLift = 0.3, seatCount = 3, chairDepth = 0.275

    var west: Double { Double(x0) - 0.5 }
    var north: Double { Double(y0) - 0.5 }
    var table: SIMD2<Double> { SIMD2(Double(x0) + 2, Double(y0) + 1) }

    var consoles: [Console] {
        [Console(at: SIMD2(Double(x0) + 0.95, north + 0.35), yaw: 0),
         Console(at: SIMD2(Double(x0) + 3.05, north + 0.35), yaw: 0),
         Console(at: SIMD2(Double(x0) + 4.5 - 0.22, Double(y0) + 1.2), yaw: -.pi / 2)]
    }

    var seats: [Spot] {
        consoles.map { c in
            let back = SIMD2(sin(c.yaw), cos(c.yaw))
            return Spot(at: c.at + back * 0.33, facing: atan2(-back.x, -back.y), seated: true)
        }
    }

    var stands: [Spot] {
        [0.0, 0.85, -0.85].map { a in
            let out = SIMD2(sin(a), cos(a))
            return Spot(at: table + out * (MissionControl.tableRadius + Hands.arm + 0.04), facing: atan2(-out.x, -out.y), seated: false)
        }
    }

    var spots: [Spot] { seats + stands }

    var boards: (annunciator: Double, flaps: [Double], clock: Double) {
        (Double(x0) + 2, [Double(x0) + 0.4, Double(x0) + 3.6], Double(x0) + 2)
    }
    static let boardBottom = 0.46, boardTop = 1.06
}

extension Station {
    var missionControl: MissionControl? {
        guard let room = rooms["kind:mission"], room.cells.count == 15 else { return nil }
        return MissionControl(x0: room.cells.map(\.x).min()!, y0: room.cells.map(\.y).min()!)
    }

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

    func gymSpots(gym: Room) -> [SIMD2<Double>] {
        let door = doorCell(of: gym.key)
        let maxY = gym.cells.map(\.y).max()!
        let sign = Cell(x: gym.cells.filter { $0.y == maxY }.map(\.x).max()!, y: maxY)
        var tiles = gym.cells.filter { $0 != door && $0 != sign }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        while tiles.count < 4, let more = gym.cells.first(where: { !tiles.contains($0) }) { tiles.append(more) }
        return tiles.prefix(4).map { SIMD2(offset.x + Double($0.x), offset.y + Double($0.y)) }
    }

    func gymOutward(gym: Room, at spot: SIMD2<Double>) -> SIMD2<Double> {
        let cx = offset.x + Double(gym.cells.map(\.x).reduce(0, +)) / Double(gym.cells.count)
        let cy = offset.y + Double(gym.cells.map(\.y).reduce(0, +)) / Double(gym.cells.count)
        return SIMD2(spot.x >= cx ? 1 : -1, spot.y >= cy ? 1 : -1)
    }

    func gymStand(gym: Room, _ kind: Command.Workout) -> (cell: Cell, spot: SIMD2<Double>, facing: Double) {
        let world = gymSpots(gym: gym)[kind.rawValue]
        let local = SIMD2(world.x - offset.x, world.y - offset.y)
        let cell = Cell(x: Int(local.x.rounded()), y: Int(local.y.rounded()))
        switch kind {
        case .treadmill: return (cell, local + SIMD2(0, -0.05), 0)
        case .bench: return (cell, local + SIMD2(0, -0.18), 0)
        case .bag:
            let out = gymOutward(gym: gym, at: world)
            return (cell, local - out * 0.2, atan2(out.x, out.y))
        case .mat: return (cell, local, .pi / 4)
        }
    }
}
