// Where a station's fixtures stand: the bath's bowl and shower, the gym's four pieces. Facts of the
// floor plan, read by the simulation to walk a body to them and by the scene to draw them.

import Foundation

extension Station {
    /// The bath's two fixtures and the corner of its tile each backs into: the toilet and the shower
    /// take the tiles that are neither the doorway nor the far corner the room's name is cut into.
    /// The corner is the unit direction from the room's middle out to the tile's outer wall corner.
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

    /// Where the bowl stands, in world x/z: into the toilet tile's corner, the tank against the wall behind it.
    func bowlSpot(bath: Room) -> SIMD2<Double> {
        let f = bathFixtures(bath: bath)
        return SIMD2(offset.x + Double(f.toilet.x) + 0.22 * f.toiletCorner.x, offset.y + Double(f.toilet.y) + 0.22 * f.toiletCorner.y)
    }

    /// Where the shower's water comes from, in world x/z: the nozzle over the shower tile's corner.
    func showerNozzle(bath: Room) -> SIMD2<Double> {
        let f = bathFixtures(bath: bath)
        return SIMD2(offset.x + Double(f.shower.x) + 0.3 * f.showerCorner.x, offset.y + Double(f.shower.y) + 0.25 * f.showerCorner.y)
    }

    /// Where the gym's four fixtures stand, in world coordinates: treadmill, bench, bag, mat, on the
    /// tiles that are neither the doorway nor the far corner the room's name is cut into.
    func gymSpots(gym: Room) -> [SIMD2<Double>] {
        let door = doorCell(of: gym.key)
        let maxY = gym.cells.map(\.y).max()!
        let sign = Cell(x: gym.cells.filter { $0.y == maxY }.map(\.x).max()!, y: maxY)
        var tiles = gym.cells.filter { $0 != door && $0 != sign }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        while tiles.count < 4, let more = gym.cells.first(where: { !tiles.contains($0) }) { tiles.append(more) }
        return tiles.prefix(4).map { SIMD2(offset.x + Double($0.x), offset.y + Double($0.y)) }
    }

    /// Which way is out from a gym tile: toward the nearest outer wall, for a post to stand against.
    func gymOutward(gym: Room, at spot: SIMD2<Double>) -> SIMD2<Double> {
        let cx = offset.x + Double(gym.cells.map(\.x).reduce(0, +)) / Double(gym.cells.count)
        let cy = offset.y + Double(gym.cells.map(\.y).reduce(0, +)) / Double(gym.cells.count)
        return SIMD2(spot.x >= cx ? 1 : -1, spot.y >= cy ? 1 : -1)
    }

    /// The tile a workout stands on, and the exact spot and facing for it.
    func gymStand(gym: Room, _ kind: Command.Workout) -> (cell: Cell, spot: SIMD2<Double>, facing: Double) {
        let world = gymSpots(gym: gym)[kind.rawValue]
        let local = SIMD2(world.x - offset.x, world.y - offset.y)
        let cell = Cell(x: Int(local.x.rounded()), y: Int(local.y.rounded()))
        switch kind {
        case .treadmill: return (cell, local + SIMD2(0, -0.05), 0)               // on the slab, facing the rail
        case .bench: return (cell, local + SIMD2(0, -0.18), 0)                   // lying under the bar
        case .bag:                                                               // a step in from the post, squared up to the bag
            let out = gymOutward(gym: gym, at: world)
            return (cell, local - out * 0.2, atan2(out.x, out.y))
        case .mat: return (cell, local, .pi / 4)                                  // the middle of the mat
        }
    }
}
