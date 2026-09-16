// How a place is drawn. Every theme draws the same six layers (THEMES.md): the world round the station,
// the input, the output, the center, the idle areas and the growth zone. The scene owns where everything
// stands, what it is named, what the walks go round and how things move; a look only says what a thing is
// drawn as. Every requirement has a default, the classic station's, so a look overrides only what it changes.

import AppKit
import SceneKit

protocol Look {
    // MARK: the world

    /// Whether tiles that look alike may share one geometry and one material. True for a look that
    /// decides a tile's appearance once and leaves it: a station of four hundred tiles then needs a
    /// dozen geometries rather than two thousand, and a redraw costs a third of what it did.
    ///
    /// A look that wants to reach into a single tile afterwards — one that fades, flickers, or is tinted
    /// by something that happens on it — says false and is given a tile of its own each time, which it
    /// may do as it likes with.
    var sharesTiles: Bool { get }

    /// The colour past the edge of everything.
    var background: NSColor { get }
    /// The view's turn about the vertical before the user turns it.
    var viewYaw: Double { get }
    /// What lies beyond the stations, into `root`; returns what drifts, each with its velocity.
    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)]
    /// The ground round `stations`, into `root`, rebuilt with the floor.
    func ground(under stations: [Station], into root: SCNNode)

    // MARK: the input: the bay and the airlock

    /// The bay and the airlock drawn whole, in world coordinates, or nil for tiles. The scene keeps the doors,
    /// the landing slots and the carriers' stands where they are, whatever is drawn round them.
    func input(_ station: Station) -> SetPiece?
    /// The frame over the airlock's doorway, `width` across, with a tile under each of `spans` (x from its
    /// middle). The posts are the scene's, since the walks go between them; `showsPosts` says if they are drawn.
    func airlockFrame(width: Double, spans: [Double], tint: NSColor) -> (node: SCNNode, showsPosts: Bool)
    /// A shuttle, nose along +x, its hull's middle at the origin.
    func shuttle(color: NSColor) -> SCNNode
    /// A ship's position and heading along its flight, in the station's own coordinates; nil keeps the
    /// simulation's path, down from the sky onto the slot. The simulation still says when, and which slot.
    func shipPose(_ leg: ShipLeg) -> (pos: SIMD3<Double>, yaw: Double)?

    // MARK: the output: decon, storage, the deck and the pad

    /// Decon, storage, the deck and the pad drawn whole, in world coordinates, or nil for tiles. The scene
    /// keeps the decon hatch, the storage console and every crate's spot where they are.
    func output(_ station: Station, deckInUse: Bool) -> SetPiece?
    /// The decon hatch's frame for a hatch facing along `facing`, and the height its light hangs at.
    func hatchFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double)
    /// A rocket standing on the origin, with children named "hatch" and "flame" the scene reaches for.
    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode
    /// How a rocket leaves once its release merges; the scene lights the flame first and takes it away after.
    func launch(_ rocket: SCNNode) -> SCNAction

    // MARK: the center

    /// The monolith, standing on the origin: the landmark that says what kind of place this is.
    func monolith() -> SCNNode

    // MARK: the idle areas

    /// The fixed rooms' furniture, placed in the world as the room stands: the lounge, the bath and the gym.
    func furnishLounge(_ lounge: Room, in station: Station) -> Furnishing
    func furnishBath(_ bath: Room, in station: Station) -> Furnishing
    func furnishGym(_ gym: Room, in station: Station) -> Furnishing
    /// A bed, `level` 0 on the floor and 1 the upper bunk, centred on the origin at its own height.
    func bed(level: Int) -> SCNNode

    // MARK: the growth zone: offices, fixed rooms' floors and the hallway

    /// How far the floor's top stands over a tile's plane: flat marks on the floor go above it.
    var floorTop: Double { get }
    /// Whether the hallway gets its small dark dots.
    var dotsHallway: Bool { get }
    /// Whether floors of different owners are parted by a dark line.
    var drawsBorders: Bool { get }
    /// Whether a floor's square plane is drawn. Hidden, the tile still names, dims and unfolds its detail.
    func drawsPlane(_ floor: Floor) -> Bool
    /// The colour a tile's plane is drawn in, from the colour the scene gives that floor.
    func floorColor(_ color: NSColor, floor: Floor) -> NSColor
    /// Hung under a floor tile's plane, in the plane's frame.
    func tileDetail(_ tile: Tile) -> SCNNode?
    /// Recolour a floor tile and whatever the look hung on it.
    func tint(tile: SCNNode, _ color: NSColor)
    /// A prop for an office, in the station's own cells.
    func dress(office room: Room, in station: Station) -> SCNNode?

    // MARK: people, and anything else

    /// A figure to stand in a minion's box, or nil to draw the box; `id` is the minion's, for a look that varies them.
    func figure(id: String, crew: Bool, height: Double) -> SCNNode?
    /// Pose that figure `torso` tall, hung from the middle of a box `height` tall: the full height standing.
    func pose(figure: SCNNode, height: Double, torso: Double)
    /// Props for a station, in the station's own cells, in spots nobody stands on.
    func dress(station: Station) -> [SCNNode]
    /// What a minion holds for `tool`, in its body's frame (`height` tall, `depth` deep), or nil for the classic
    /// piece. The scene swings a child named "swing" as it swings the hammer, turns one named "aim" as it turns
    /// the torch, blinks one named "tip", and lights "wandTip" and "wandLight" while a crate is in the air.
    func tool(_ tool: Minion.Tool, height: Double, depth: Double) -> SCNNode?
    /// Whether working a message throws welding sparks.
    var workSparks: Bool { get }
    /// A message waiting to be worked, standing on the origin, or nil for the classic pyramid.
    func message(color: NSColor, floor: NSColor) -> SCNNode?
}

/// What every look gets unless it draws its own: the classic station, adrift in space.
extension Look {
    var sharesTiles: Bool { true }
    var background: NSColor { Palette.void }
    var viewYaw: Double { .pi / 4 }
    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)] { Classic.backdrop(into: root) }
    func ground(under stations: [Station], into root: SCNNode) {}

    func input(_ station: Station) -> SetPiece? { nil }
    func airlockFrame(width: Double, spans: [Double], tint: NSColor) -> (node: SCNNode, showsPosts: Bool) {
        Classic.airlockFrame(width: width, spans: spans, tint: tint)
    }
    func shuttle(color: NSColor) -> SCNNode { Classic.shuttle(color: color) }
    func shipPose(_ leg: ShipLeg) -> (pos: SIMD3<Double>, yaw: Double)? { nil }

    func output(_ station: Station, deckInUse: Bool) -> SetPiece? { nil }
    func hatchFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double) { Classic.hatchFrame(facing: facing) }
    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode { Classic.rocket(color: color, tall: tall, cargo: cargo) }
    func launch(_ rocket: SCNNode) -> SCNAction { Classic.launch() }

    func monolith() -> SCNNode { Classic.monolith() }

    func furnishLounge(_ lounge: Room, in station: Station) -> Furnishing { Classic.lounge(lounge, in: station) }
    func furnishBath(_ bath: Room, in station: Station) -> Furnishing { Classic.bath(bath, in: station) }
    func furnishGym(_ gym: Room, in station: Station) -> Furnishing { Classic.gym(gym, in: station) }
    func bed(level: Int) -> SCNNode { Classic.bed(level: level, floorTop: floorTop) }

    var floorTop: Double { 0 }
    var dotsHallway: Bool { true }
    var drawsBorders: Bool { true }
    func drawsPlane(_ floor: Floor) -> Bool { true }
    func floorColor(_ color: NSColor, floor: Floor) -> NSColor { color }
    func tileDetail(_ tile: Tile) -> SCNNode? { nil }
    func tint(tile: SCNNode, _ color: NSColor) { tile.geometry?.firstMaterial?.diffuse.contents = color }
    func dress(office room: Room, in station: Station) -> SCNNode? { nil }

    func figure(id: String, crew: Bool, height: Double) -> SCNNode? { nil }
    func pose(figure: SCNNode, height: Double, torso: Double) {}
    func dress(station: Station) -> [SCNNode] { [] }
    func tool(_ tool: Minion.Tool, height: Double, depth: Double) -> SCNNode? { nil }
    var workSparks: Bool { true }
    func message(color: NSColor, floor: NSColor) -> SCNNode? { nil }
}

/// What a floor tile is: `room` an office, `fixed` the lounge, the dorm, the bath or the gym.
enum Floor { case hallway, room, fixed, yard, bay, airlock }

/// A floor tile as a look sees it.
struct Tile {
    let floor: Floor
    let color: NSColor
    /// Edges with no floor beyond, numbered round the tile z-, x-, z+, x+.
    let open: Set<Int>
    /// Edges with another owner's floor beyond and no doorway, and what floor that is.
    let walled: [Int: Floor]
    /// Which of the eight neighbours are this owner's floor too: bit k for `Tile.around[k]`.
    let same: UInt8
    /// The eight neighbours in turn from z- round by x+: (dx, dz).
    static let around: [(Int, Int)] = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
}

/// A fixed area of the station, by the name the scene gives its nodes for the pointer and the clicks.
enum Area: String { case bay = "hangar", airlock, storage, deck, pad, decon }

/// A fixed area drawn whole: nodes in world coordinates, each under the area it stands for.
struct SetPiece {
    var parts: [Area: [SCNNode]] = [:]
    mutating func add(_ node: SCNNode, as area: Area) { parts[area, default: []].append(node) }
}

/// Where a ship is in its flight, for a look that draws the path itself: the phase and how far through it,
/// the slot it serves in the station's own coordinates, and the side it leaves toward, 1 or -1.
struct ShipLeg {
    let phase: Command.Phase
    let progress: Double
    let slot: SIMD2<Double>
    let side: Double
}

/// The look the scene draws with, swapped when the theme changes.
enum Looks {
    private(set) static var theme: Theme = .classic
    private(set) static var current: Look = ClassicLook()

    static func use(_ theme: Theme) {
        self.theme = theme
        switch theme {
        case .classic: current = ClassicLook()
        case .kenney: current = KenneyLook()
        }
    }
}

/// The fleet's footprint in world units: each station's bounds with its offset, and the whole; nil with no stations.
func fleetFootprint(_ stations: [Station]) -> (lo: SIMD2<Double>, hi: SIMD2<Double>, each: [(lo: SIMD2<Double>, hi: SIMD2<Double>)])? {
    var lo = SIMD2<Double>(.infinity, .infinity), hi = SIMD2<Double>(-.infinity, -.infinity)
    var each: [(lo: SIMD2<Double>, hi: SIMD2<Double>)] = []
    for st in stations {
        let b = st.bounds
        let a = SIMD2(Double(b.min.x) + st.offset.x - 0.5, Double(b.min.y) + st.offset.y - 0.5)
        let z = SIMD2(Double(b.max.x) + st.offset.x + 0.5, Double(b.max.y) + st.offset.y + 0.5)
        each.append((a, z))
        lo = pointwiseMin(lo, a); hi = pointwiseMax(hi, z)
    }
    guard lo.x.isFinite else { return nil }
    return (lo: lo, hi: hi, each: each)
}

/// Spots a look may stand set dressing on, worked out from the plan and clear of whatever moves there.
enum Dressing {
    /// The pad's two corners farthest from every rocket slot.
    static func padCorners(_ station: Station) -> [Cell] {
        guard station.hasPad else { return [] }
        let pc = station.padCenter
        let slots = [SIMD2(0.0, 0.0), SIMD2(1.3, 0.0), SIMD2(-1.3, 0.0), SIMD2(0.0, 1.2)].map { pc + $0 }
        func clearance(_ c: Cell) -> Double { slots.map { simd_distance(SIMD2(Double(c.x), Double(c.y)), $0) }.min() ?? 0 }
        let near: [Cell] = station.padCells.filter { c in clearance(c) > 1.1 && simd_distance(SIMD2(Double(c.x), Double(c.y)), pc) < 2.5 }
        let sorted: [Cell] = near.sorted { a, b in (clearance(a), a.y, a.x) > (clearance(b), b.y, b.x) }
        return Array(sorted.prefix(2))
    }

    /// The bay's cell farthest from the slots the ships drop crates on and from the airlock, when one is clear.
    static func bayParking(_ station: Station) -> Cell? {
        guard station.hasHangar, !station.hangarCells.isEmpty else { return nil }
        let keepOff = station.hangarSlots + station.airlockCells.map { SIMD2(Double($0.x), Double($0.y)) }
        func clearance(_ c: Cell) -> Double { keepOff.map { simd_distance(SIMD2(Double(c.x), Double(c.y)), $0) }.min() ?? 0 }
        guard let c = station.hangarCells.max(by: { (clearance($0), $0.y, $0.x) < (clearance($1), $1.y, $1.x) }), clearance(c) > 0.9 else { return nil }
        return c
    }

    /// The office's farthest cell from its door, and the way out through an outer wall of it: a side with
    /// nothing beyond before anything else, never the doorway.
    static func officeWall(_ room: Room, in station: Station) -> (cell: Cell, out: SIMD2<Double>)? {
        let cells = Set(room.cells)
        guard let door = station.doorCell(of: room.key), let outside = station.doorOutside(of: room.key),
              let far = room.cells.max(by: { a, b in
                  (abs(a.x - door.x) + abs(a.y - door.y), -a.y, -a.x) < (abs(b.x - door.x) + abs(b.y - door.y), -b.y, -b.x)
              }) else { return nil }
        let sides = [Cell(x: far.x, y: far.y - 1), Cell(x: far.x, y: far.y + 1), Cell(x: far.x - 1, y: far.y), Cell(x: far.x + 1, y: far.y)]
        let walls = sides.filter { !cells.contains($0) && !($0 == outside && far == door) }
        guard let wall = walls.first(where: { station.room(at: $0) == nil && !station.isCorridor($0) }) ?? walls.first else { return nil }
        return (far, SIMD2(Double(wall.x - far.x), Double(wall.y - far.y)))
    }
}
