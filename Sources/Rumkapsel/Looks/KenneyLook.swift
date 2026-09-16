// Kenney Space Center: the same floor plan on the ground, laid out as the Cape is, built from Kenney's
// Space Kit, Modular Space Kit and Nature Kit (CC0). Where a model is missing from the bundle, the
// classic piece stands in, so a broken install draws a station rather than holes.

import AppKit
import SceneKit

struct KenneyLook: Look {
    var background: NSColor { Kit.sky }
    /// Turned about so the yard and its pad face right, toward the sea.
    var viewYaw: Double { .pi / 4 + .pi }
    var floorTop: Double { Kit.plateTop }
    /// The kit's plates have marks of their own.
    var dotsHallway: Bool { false }

    /// On the ground there is nothing to drift.
    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)] { [] }

    /// The cape: a lawn, and the sea past the pads, its edge wandering rather than ruled. Every palm, rock
    /// and tuft is keyed to the cell it stands on in its own station's plan, so growing an office moves
    /// nothing that was already there.
    func ground(under stations: [Station], into root: SCNNode) {
        guard let fp = fleetFootprint(stations), let cape = Cape(stations) else { return }
        let lo = SIMD2(cape.shore - 90, fp.lo.y - 46), hi = SIMD2(fp.hi.x + 40, fp.hi.y + 46)
        let lawn = SCNNode(geometry: SCNPlane(width: hi.x - cape.shore + 8, height: hi.y - lo.y))
        lawn.geometry!.firstMaterial = lit(Kit.grass)
        lawn.eulerAngles.x = -.pi / 2
        lawn.position = v3((cape.shore - 8 + hi.x) / 2, -0.06, (lo.y + hi.y) / 2)
        root.addChildNode(lawn)

        // One sampling of how far a point lies to landward of the coast, cut at four levels: the open sea,
        // the shallows over it, the foam at the line itself, and the sand behind it.
        let land = Shapes.sample(from: lo, to: hi, step: 0.5) { p in p.x - cape.shoreline(p.y) }
        let bands: [(Shapes.Grid, NSColor, Double)] = [
            (land.map { _, d in -d }, Kit.water, -0.05),
            (land.map { _, d in min(-d, 2.6 + d) }, Kit.water.lighter(0.18), -0.045),
            (land.map { _, d in min(0.5 - d, 0.5 + d) }, NSColor(rgb: (0.93, 0.97, 0.99)), -0.04),
            (land.map { _, d in min(d, 1.5 - d) }, NSColor(rgb: (0.89, 0.83, 0.66)), -0.043),
        ]
        for (grid, color, y) in bands {
            if let n = Shapes.node(Shapes.fill(grid), color, y: y) { root.addChildNode(n) }
        }

        // Palms in groves behind the sand, scrub in thickets over the lawn, both thinning to bare ground
        // between: what stands on a cell, and how big and which way about, all follow from the cell itself.
        let palms = ["tree_palm", "tree_palmTall", "tree_palmBend", "tree_palmDetailedShort"]
        let scrub = ["grass", "grass", "grass", "grass", "grass", "grass_large", "grass_large", "grass_large",
                     "plant_bush", "plant_bushLarge", "flower_yellowA", "flower_redA", "rock_smallA", "rock_smallB"]
        for z in Int(lo.y.rounded())...Int(hi.y.rounded()) {
            for x in Int((cape.shore - 2).rounded())...Int(hi.x.rounded()) {
                let p = SIMD2(Double(x), Double(z))
                guard let home = cape.nearest(p), !home.claims(p, within: 1.4) else { continue }
                let cell = home.cell(p)
                let h = Noise.hash(cell.x, cell.y, seed: home.seed)
                let d = p.x - cape.shoreline(p.y)
                guard d > 1.4 else { continue }   // never in the water or on the wet sand
                let q = SIMD2(Double(cell.x), Double(cell.y))
                let grove = Noise.fbm(q, scale: 26, seed: 9)
                let onSand = d < 8 && grove > 0.47
                let density = onSand ? (grove - 0.47) * 2.4
                                     : max(0, Noise.fbm(q, scale: 23, seed: 3) - 0.50) * 2.6
                guard h < density else { continue }
                let pick = Noise.hash(cell.x, cell.y, seed: home.seed + 31)
                // A boulder now and then, wherever the ground is open enough to notice one.
                let names = onSand ? palms : (pick < 0.03 ? ["rock_largeA"] : scrub)
                let name = names[min(names.count - 1, Int(pick * Double(names.count)))]
                guard let n = Kit.node(name, from: .nature, tint: Kit.scrubTint) else { continue }
                let s = 0.7 + 0.4 * Noise.hash(cell.x, cell.y, seed: home.seed + 57)
                n.scale = SCNVector3(s, s, s)
                n.eulerAngles.y = 2 * .pi * Noise.hash(cell.x, cell.y, seed: home.seed + 83)
                let jitter = SIMD2(Noise.hash(cell.x, cell.y, seed: home.seed + 11) - 0.5,
                                   Noise.hash(cell.x, cell.y, seed: home.seed + 19) - 0.5) * 0.7
                n.position = v3(p.x + jitter.x, -0.03, p.y + jitter.y)
                root.addChildNode(n)
            }
        }
    }

    /// One of the kit's platforms, kerbed on the open edges, the dark line between owners kept as it is.
    func tileDetail(_ tile: Tile) -> SCNNode? {
        guard let plate = Kit.platform(open: tile.open, color: tile.color) else { return nil }
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
            guard let gate = Kit.gate(yaw: 0) else { return Classic.airlockFrame(width: width, spans: spans, tint: tint) }
            gate.position = v3(x, 0, 0)
            row.addChildNode(gate)
        }
        return (row, false)
    }

    func hatchFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double) {
        guard let gate = Kit.gate(yaw: facing.x == 0 ? 0 : .pi / 2) else { return Classic.hatchFrame(facing: facing) }
        return (gate, 0.9)
    }

    /// The kit's comms tower, its dish turning slowly over the plaza.
    func monolith() -> SCNNode { Kit.tower() ?? Classic.monolith() }

    /// Astronauts; the crew wear the other suit.
    func figure(id: String, crew: Bool, height: Double) -> SCNNode? { Kit.astronaut(crew: crew, height: height) }

    /// The astronaut has legs of its own: on a seat it shortens, feet at the box's new foot.
    func pose(figure: SCNNode, height: Double, torso: Double) {
        let s = height / Kit.astronautHeight
        figure.scale = SCNVector3(s, s * torso / height, s)
        figure.position = v3(0, -torso / 2, -0.03)
    }

    func shuttle(color: NSColor) -> SCNNode { Kit.craft(color: color) ?? Classic.shuttle(color: color) }

    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode {
        Kit.rocketProp(color: color, tall: tall, cargo: cargo) ?? Classic.rocket(color: color, tall: tall, cargo: cargo)
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

/// The cape the stations stand on: where the water's edge runs, and whose plan a patch of ground belongs to.
/// Everything the look scatters is keyed to a cell of that station's own plan, so the ground keeps its
/// character as the station grows instead of being reshuffled by the fleet's new extent.
private struct Cape {
    /// One station's claim on the ground: its floor in its own cells, and where that sits in the world.
    struct Home {
        let offset: SIMD2<Double>
        let floor: Set<Cell>
        let lo: SIMD2<Double>, hi: SIMD2<Double>
        let seed: Int

        func cell(_ p: SIMD2<Double>) -> Cell {
            Cell(x: Int((p.x - offset.x).rounded()), y: Int((p.y - offset.y).rounded()))
        }

        /// Whether the station's floor reaches this point: the cells about it, not its bounding box, so the
        /// lawn runs into the notches between the arms.
        func claims(_ p: SIMD2<Double>, within margin: Double) -> Bool {
            let c = cell(p), r = Int(margin.rounded(.up))
            for dz in -r...r {
                for dx in -r...r where floor.contains(Cell(x: c.x + dx, y: c.y + dz)) {
                    let at = offset + SIMD2(Double(c.x + dx), Double(c.y + dz))
                    if simd_length(simd_max(simd_abs(p - at) - SIMD2(0.5, 0.5), SIMD2(repeating: 0))) < margin { return true }
                }
            }
            return false
        }

        func reach(to p: SIMD2<Double>) -> Double {
            let q = simd_max(simd_max(lo - p, p - hi), SIMD2(repeating: 0))
            return simd_length(q)
        }
    }

    let homes: [Home]
    /// The line the water's edge wanders about, a causeway's length past the seaward pad.
    let shore: Double
    private let phase: Double

    init?(_ stations: [Station]) {
        var homes: [Home] = []
        var shore = Double.infinity
        for st in stations {
            let floor = Set(st.allCells)
            guard let b = floor.isEmpty ? nil : st.bounds else { continue }
            homes.append(Home(offset: st.offset, floor: floor,
                              lo: st.offset + SIMD2(Double(b.min.x), Double(b.min.y)),
                              hi: st.offset + SIMD2(Double(b.max.x), Double(b.max.y)),
                              seed: abs(st.name.hashValue % 9973)))
            let west = st.hasPad ? st.padCells.map(\.x).min() ?? b.min.x : b.min.x
            shore = min(shore, st.offset.x + Double(west) - 4)
        }
        guard !homes.isEmpty, shore.isFinite else { return nil }
        self.homes = homes
        self.shore = shore
        // The wobble is set against the seaward station's own plan, so the coast keeps its shape where it is.
        phase = homes.min { $0.lo.x < $1.lo.x }?.offset.y ?? 0
    }

    /// Where the water's edge stands at this distance along the coast: a long slow bay with a smaller
    /// wander over it, so no stretch of it is straight.
    func shoreline(_ z: Double) -> Double {
        let t = z - phase
        return shore + (Noise.fbm(SIMD2(0, t), scale: 58) - 0.5) * 17 + (Noise.fbm(SIMD2(0, t), scale: 16, seed: 5) - 0.5) * 6
    }

    /// Whose ground this is: the station whose floor lies nearest.
    func nearest(_ p: SIMD2<Double>) -> Home? {
        homes.min { $0.reach(to: p) < $1.reach(to: p) }
    }
}
