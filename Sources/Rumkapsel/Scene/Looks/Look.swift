import AppKit
import SceneKit

struct LaunchPose {
    var offset = SIMD3<Double>(0, 0, 0)
    var opacity = 1.0
    var flame = 0.0
}

enum Timing {
    static func easeIn(_ x: Double) -> Double { bezier(x, 0.42, 1) }
    static func easeInOut(_ x: Double) -> Double { bezier(x, 0.42, 0.58) }
    static func clamped(_ x: Double) -> Double { min(1, max(0, x)) }

    private static func bezier(_ x: Double, _ x1: Double, _ x2: Double) -> Double {
        let x = clamped(x)
        var lo = 0.0, hi = 1.0
        for _ in 0..<32 {
            let t = (lo + hi) / 2, u = 1 - t
            if 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t < x { lo = t } else { hi = t }
        }
        let t = (lo + hi) / 2
        return 3 * (1 - t) * t * t + t * t * t
    }
}

protocol Look {
    // MARK: the world

    var sharesTiles: Bool { get }

    var background: NSColor { get }
    var viewYaw: Double { get }
    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)]
    func ground(under stations: [Station], into root: SCNNode)

    // MARK: the input: the bay

    func input(_ station: Station) -> SetPiece?
    func shuttle(color: NSColor) -> SCNNode
    func shipPose(_ leg: ShipLeg) -> (pos: SIMD3<Double>, yaw: Double)?
    var drawsBerthHexes: Bool { get }
    var berthHexHeight: Double { get }
    var hangarField: Bool { get }
    func hullWall(width: Double, depth: Double, doorway: Double, doorTop: Double) -> SCNNode?

    // MARK: the output: decon, storage, the deck and the pad

    func output(_ station: Station, deckInUse: Bool) -> SetPiece?
    func doorFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double)
    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode
    func launch(at t: Double) -> LaunchPose
    var launchSeconds: Double { get }
    var rocketFollowsLoad: Bool { get }

    // MARK: the center

    func monolith() -> SCNNode

    // MARK: the idle areas

    func furnishLounge(_ lounge: Room, in station: Station) -> Furnishing
    func furnishBath(_ bath: Room, in station: Station) -> Furnishing
    func furnishGym(_ gym: Room, in station: Station) -> Furnishing
    func furnishGalley(_ galley: Galley, in station: Station) -> Furnishing
    func bed(level: Int) -> SCNNode

    // MARK: the growth zone: offices, fixed rooms' floors and the hallway

    var floorTop: Double { get }
    var dotsHallway: Bool { get }
    var drawsBorders: Bool { get }
    var rimsOffices: Bool { get }
    func drawsPlane(_ floor: Floor) -> Bool
    func floorColor(_ color: NSColor, floor: Floor) -> NSColor
    func tileDetail(_ tile: Tile) -> SCNNode?
    func tint(tile: SCNNode, _ color: NSColor)
    func planet(name: String, color: NSColor, radius: Double) -> SCNNode
    func dress(office room: Room, in station: Station, sign: OfficeSign) -> SCNNode?

    // MARK: people, and anything else

    func figure(id: String, crew: Bool, height: Double) -> SCNNode?
    func pose(figure: SCNNode, height: Double, torso: Double)
    func dress(station: Station) -> [SCNNode]
    func crate(color: NSColor) -> SCNNode?
    func hold(tall: Bool) -> SCNNode?
    func jetpack(height: Double, depth: Double) -> SCNNode?
    func padDrone() -> SCNNode?
    var writesOnFloor: Bool { get }
    func tool(_ tool: Minion.Tool, height: Double, depth: Double) -> SCNNode?
    var workSparks: Bool { get }
    var detailsFloors: Bool { get }
    func message(color: NSColor, floor: NSColor) -> SCNNode?
}

extension Look {
    var sharesTiles: Bool { true }
    var background: NSColor { Palette.void }
    var viewYaw: Double { .pi / 4 }
    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)] { Classic.backdrop(into: root) }
    func ground(under stations: [Station], into root: SCNNode) {}

    func input(_ station: Station) -> SetPiece? { nil }
    func shuttle(color: NSColor) -> SCNNode { Classic.shuttle(color: color) }
    func shipPose(_ leg: ShipLeg) -> (pos: SIMD3<Double>, yaw: Double)? { nil }
    var drawsBerthHexes: Bool { true }
    var berthHexHeight: Double { 0.009 }
    var hangarField: Bool { true }
    func hullWall(width: Double, depth: Double, doorway: Double, doorTop: Double) -> SCNNode? {
        Classic.hullWall(width: width, depth: depth, doorway: doorway, doorTop: doorTop)
    }

    func output(_ station: Station, deckInUse: Bool) -> SetPiece? { nil }
    func doorFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double) { Classic.doorFrame(facing: facing) }
    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode { Classic.rocket(color: color, tall: tall, cargo: cargo) }
    func launch(at t: Double) -> LaunchPose { Classic.launch(at: t) }
    var launchSeconds: Double { Classic.launchSeconds }
    var rocketFollowsLoad: Bool { false }

    func monolith() -> SCNNode { Classic.monolith() }

    func furnishLounge(_ lounge: Room, in station: Station) -> Furnishing { Classic.lounge(lounge, in: station) }
    func furnishBath(_ bath: Room, in station: Station) -> Furnishing { Classic.bath(bath, in: station) }
    func furnishGym(_ gym: Room, in station: Station) -> Furnishing { Classic.gym(gym, in: station) }
    func furnishGalley(_ galley: Galley, in station: Station) -> Furnishing { Classic.galley(galley, in: station) }
    func bed(level: Int) -> SCNNode { Classic.bed(level: level, floorTop: floorTop) }

    var floorTop: Double { 0 }
    var dotsHallway: Bool { true }
    var drawsBorders: Bool { true }
    var rimsOffices: Bool { true }
    func drawsPlane(_ floor: Floor) -> Bool { true }
    func floorColor(_ color: NSColor, floor: Floor) -> NSColor { color }
    func tileDetail(_ tile: Tile) -> SCNNode? { nil }
    func tint(tile: SCNNode, _ color: NSColor) { tile.geometry?.firstMaterial?.diffuse.contents = color }
    func planet(name: String, color: NSColor, radius: Double) -> SCNNode { Planets.make(name: name, color: color, radius: radius) }
    func dress(office room: Room, in station: Station, sign: OfficeSign) -> SCNNode? { nil }

    func figure(id: String, crew: Bool, height: Double) -> SCNNode? { nil }
    func pose(figure: SCNNode, height: Double, torso: Double) {}
    func dress(station: Station) -> [SCNNode] { [] }
    func crate(color: NSColor) -> SCNNode? { nil }
    func hold(tall: Bool) -> SCNNode? { nil }
    func jetpack(height: Double, depth: Double) -> SCNNode? { nil }
    func padDrone() -> SCNNode? { nil }
    var writesOnFloor: Bool { true }
    func tool(_ tool: Minion.Tool, height: Double, depth: Double) -> SCNNode? { nil }
    var workSparks: Bool { true }
    var detailsFloors: Bool { true }
    func message(color: NSColor, floor: NSColor) -> SCNNode? { nil }
}

enum Floor { case hallway, room, fixed, yard, pad, bay }

struct Tile {
    let floor: Floor
    let color: NSColor
    let open: Set<Int>
    let walled: [Int: Floor]
    let same: UInt8
    static let around: [(Int, Int)] = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
}

struct OfficeSign {
    let number: Int?
    let who: String?
    let name: String
}

enum Area: String { case bay = "hangar", storage, deck, pad, decon }

struct SetPiece {
    var parts: [Area: [SCNNode]] = [:]
    mutating func add(_ node: SCNNode, as area: Area) { parts[area, default: []].append(node) }
}

struct ShipLeg {
    let phase: Command.Phase
    let progress: Double
    let slot: SIMD2<Double>
    let side: Double
}

enum Looks {
    private(set) static var theme: Theme = .classic
    private(set) static var current: Look = ClassicLook()

    static func use(_ theme: Theme) {
        self.theme = theme
        switch theme {
        case .classic: current = ClassicLook()
        case .kenney: current = KenneyLook()
        case .kingdom: current = KingdomLook()
        }
    }
}

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

enum Dressing {
    static func padCorners(_ station: Station) -> [Cell] {
        guard station.hasPad else { return [] }
        let pc = station.hall.padCenter
        let slots = station.hall.padSlots
        func clearance(_ c: Cell) -> Double { slots.map { simd_distance(SIMD2(Double(c.x), Double(c.y)), $0) }.min() ?? 0 }
        let near: [Cell] = station.hall.padCells.filter { c in clearance(c) > 1.1 && simd_distance(SIMD2(Double(c.x), Double(c.y)), pc) < 2.5 }
        let sorted: [Cell] = near.sorted { a, b in (clearance(a), a.y, a.x) > (clearance(b), b.y, b.x) }
        return Array(sorted.prefix(2))
    }

    static func bayParking(_ station: Station) -> Cell? {
        guard station.hasHangar, !station.hangarCells.isEmpty else { return nil }
        let keepOff = station.hangarSlots + (station.bayDoor.map { [SIMD2(Double($0.inside.x), Double($0.inside.y))] } ?? [])
        func clearance(_ c: Cell) -> Double { keepOff.map { simd_distance(SIMD2(Double(c.x), Double(c.y)), $0) }.min() ?? 0 }
        guard let c = station.hangarCells.max(by: { (clearance($0), $0.y, $0.x) < (clearance($1), $1.y, $1.x) }), clearance(c) > 0.9 else { return nil }
        return c
    }
}
