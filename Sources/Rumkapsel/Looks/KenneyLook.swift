// Kenney Space Center: the same floor plan on the ground, laid out as the Cape is, built from Kenney's
// Space Kit, Modular Space Kit and Nature Kit (CC0). Where a model is missing from the bundle, the
// classic piece stands in, so a broken install draws a station rather than holes.

import AppKit
import SceneKit

struct KenneyLook: Look {
    private let classic = ClassicLook()

    var background: NSColor { Kit.sky }
    /// Turned about so the yard and its pad face right, toward the sea.
    var viewYaw: Double { .pi / 4 + .pi }
    var floorTop: Double { Kit.plateTop }
    /// The kit's plates have marks of their own.
    var dotsHallway: Bool { false }
    var drawsBorders: Bool { true }

    func floorColor(_ color: NSColor, floor: Floor) -> NSColor { color }

    /// On the ground there is nothing to drift.
    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)] { [] }

    /// A lawn to every side and the sea past the yard, so the pad stands nearest the water; palms along
    /// the shore and scrub on the grass, from a fixed seed so it stands where it stood last time.
    func ground(under stations: [Station], into root: SCNNode) {
        guard let fp = fleetFootprint(stations) else { return }
        let lo = fp.lo, hi = fp.hi
        let onStation = { (p: SIMD2<Double>, margin: Double) -> Bool in
            fp.each.contains { p.x > $0.lo.x - margin && p.x < $0.hi.x + margin && p.y > $0.lo.y - margin && p.y < $0.hi.y + margin }
        }
        // The pad stands at the fleet's west end on its causeway, so the sea begins a few tiles past it.
        let shore = (lo.x - 4).rounded()
        let mid = (lo + hi) / 2
        let reach = 140.0
        let lawn = SCNNode(geometry: SCNPlane(width: reach, height: reach * 2))
        lawn.geometry!.firstMaterial = lit(Kit.grass)
        lawn.eulerAngles.x = -.pi / 2
        lawn.position = v3(shore + reach / 2, -0.03, mid.y)
        root.addChildNode(lawn)
        let sea = SCNNode(geometry: SCNPlane(width: reach, height: reach * 2))
        sea.geometry!.firstMaterial = lit(Kit.water)
        sea.eulerAngles.x = -.pi / 2
        sea.position = v3(shore - reach / 2, -0.08, mid.y)
        root.addChildNode(sea)
        // The shore: the kit's bank tiles in a row, their grass side turned toward the station.
        let span = Int(reach / 2)
        let midZ = mid.y.rounded()
        for k in -span...span {
            guard let bank = Kit.node("ground_riverSide", from: .nature, tint: Kit.shoreTint) else { break }
            bank.eulerAngles.y = .pi / 2
            bank.position = v3(shore + 0.5, -0.03, midZ + Double(k))
            root.addChildNode(bank)
        }
        var rng = Scatter(seed: 7)
        func plant(_ name: String, at p: SIMD2<Double>, scale: Double) {
            guard let n = Kit.node(name, from: .nature, tint: Kit.scrubTint) else { return }
            n.scale = SCNVector3(scale, scale, scale)
            n.eulerAngles.y = rng.between(0, 2 * .pi)
            n.position = v3(p.x, -0.03, p.y)
            root.addChildNode(n)
        }
        // Palms along the shore, a few steps up the bank, and never on the station.
        let palms = ["tree_palm", "tree_palmTall", "tree_palmBend", "tree_palmDetailedShort"]
        for _ in 0..<26 {
            let p = SIMD2(shore + rng.between(1.2, 4.5), midZ + rng.between(-Double(span) + 2, Double(span) - 2))
            guard !onStation(p, 1.5) else { continue }
            plant(rng.pick(palms), at: p, scale: rng.between(0.75, 1.1))
        }
        // Scrub on the lawn round the fleet: tufts of grass most of all, then bushes, rocks and flowers.
        let scrub = ["grass", "grass", "grass_large", "grass_large", "plant_bush", "plant_bushLarge", "rock_smallA", "rock_smallB", "flower_yellowA", "flower_redA"]
        for _ in 0..<140 {
            let p = SIMD2(rng.between(max(shore + 1.5, lo.x - 22), hi.x + 22), rng.between(lo.y - 22, hi.y + 22))
            guard !onStation(p, 1.2) else { continue }
            plant(rng.pick(scrub), at: p, scale: rng.between(0.7, 1.1))
        }
        for _ in 0..<6 {
            let p = SIMD2(rng.between(max(shore + 3, lo.x - 22), hi.x + 22), rng.between(lo.y - 22, hi.y + 22))
            guard !onStation(p, 2) else { continue }
            plant("rock_largeA", at: p, scale: rng.between(0.8, 1.2))
        }
    }

    /// One of the kit's platforms, kerbed on the open edges, the dark line between owners kept as it is.
    func tileDetail(floor: Floor, open: Set<Int>, walled: [Int: Floor], color: NSColor) -> SCNNode? {
        guard let plate = Kit.platform(open: open, color: color) else { return nil }
        // Under a plane tilted flat: the plate set a hair above the plane, under the text on the floor.
        plate.eulerAngles.x = .pi / 2
        plate.position = SCNVector3(0, 0, Kit.plateTop - 0.05)
        return plate
    }

    func tint(tile: SCNNode, _ color: NSColor) { Kit.tint(tile: tile, color) }

    /// A row of the kit's arches across the chamber, the pane still dropping behind them.
    func airlockFrame(width: Double, spans: [Double], tint: NSColor) -> (node: SCNNode, showsPosts: Bool) {
        let row = SCNNode()
        for x in spans {
            guard let gate = Kit.gate(yaw: 0) else { return classic.airlockFrame(width: width, spans: spans, tint: tint) }
            gate.position = v3(x, 0, 0)
            row.addChildNode(gate)
        }
        return (row, false)
    }

    func hatchFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double) {
        guard let gate = Kit.gate(yaw: facing.x == 0 ? 0 : .pi / 2) else { return classic.hatchFrame(facing: facing) }
        return (gate, 0.9)
    }

    /// The kit's comms tower, its dish turning slowly over the plaza.
    func monolith() -> SCNNode { Kit.tower() ?? classic.monolith() }

    /// Astronauts; the crew wear the other suit.
    func figure(id: String, crew: Bool, height: Double) -> SCNNode? { Kit.astronaut(crew: crew, height: height) }

    /// The astronaut has legs of its own: on a seat it shortens, feet at the box's new foot.
    func pose(figure: SCNNode, height: Double, torso: Double) {
        let s = height / Kit.astronautHeight
        figure.scale = SCNVector3(s, s * torso / height, s)
        figure.position = v3(0, -torso / 2, -0.03)
    }

    func shuttle(color: NSColor) -> SCNNode { Kit.craft(color: color) ?? classic.shuttle(color: color) }

    func shipPose(_ leg: ShipLeg) -> (pos: SIMD3<Double>, yaw: Double)? { nil }

    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode {
        Kit.rocketProp(color: color, tall: tall, cargo: cargo) ?? classic.rocket(color: color, tall: tall, cargo: cargo)
    }

    /// Fuel by the pad, on its two corners clear of the rockets; a rover parked in the bay.
    func dress(station: Station) -> [SCNNode] {
        var props: [SCNNode] = []
        for (i, c) in Dressing.padCorners(station).enumerated() {
            guard let barrel = Kit.prop("machine_barrel", scale: 0.8, yaw: Double(i) * .pi / 2 + 0.4, color: NSColor(rgb: (0.75, 0.62, 0.25))) else { continue }
            barrel.position = v3(Double(c.x), 0, Double(c.y))
            props.append(barrel)
        }
        if let c = Dressing.bayParking(station), let rover = Kit.prop("rover", scale: 1.5, yaw: 0.6, color: NSColor(Colors.hangar).lighter(0.25)) {
            rover.position = v3(Double(c.x), 0, Double(c.y))
            props.append(rover)
        }
        return props
    }

    /// A computer desk against an outer wall of the office's farthest cell from the door, its screen
    /// turned into the room, so whoever stands on that cell stands at it.
    func dress(office room: Room, in station: Station) -> SCNNode? {
        guard let wall = Dressing.officeWall(room, in: station) else { return nil }
        let d = wall.out
        guard let desk = Kit.prop("desk_computer", scale: 0.8, yaw: atan2(-d.x, -d.y), color: NSColor(room.color)) else { return nil }
        desk.position = v3(Double(wall.cell.x) + d.x * 0.36, Kit.plateTop, Double(wall.cell.y) + d.y * 0.36)
        return desk
    }
}
