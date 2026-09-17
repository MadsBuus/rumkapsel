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

    // The complex is poured, not tiled: one apron under the whole of it, with each part painted on top.
    static let concrete = NSColor(rgb: (0.66, 0.67, 0.66))
    static let kerb = NSColor(rgb: (0.46, 0.47, 0.48))
    static let padPaint = NSColor(rgb: (0.34, 0.35, 0.38))
    static let hazard = NSColor(rgb: (0.82, 0.68, 0.26))
    static let bayPaint = NSColor(rgb: (0.52, 0.55, 0.62))
    static let deckPaint = NSColor(rgb: (0.42, 0.55, 0.52))
    static let paintLine = NSColor(rgb: (0.92, 0.93, 0.92))
    static let steel = NSColor(rgb: (0.72, 0.74, 0.76))

    /// A flat slab over a set of the station's cells, its edge `grow` out from them and its corners rounded,
    /// placed in the world. One sampling of the distance to the cells cut at that edge, so a run of them is
    /// one shape with no seam down the middle.
    private func slab(_ cells: [Cell], of station: Station, grow: Double, _ color: NSColor, y: Double) -> SCNNode? {
        guard !cells.isEmpty else { return nil }
        let own = Set(cells)
        // Drawn out from the cells, or in from them. Measuring in means measuring to the ring of cells just
        // outside the set: the distance to the set's own squares says only how deep one square is, so an
        // inset taken from it would cut every cell into a lozenge of its own instead of one shape.
        let from = grow >= 0 ? cells : own.flatMap { c in
            Tile.around.map { Cell(x: c.x + $0.0, y: c.y + $0.1) }
        }.filter { !own.contains($0) }
        let pts = Array(Set(from)).map { SIMD2(Double($0.x), Double($0.y)) }
        guard !pts.isEmpty else { return nil }
        let cx = cells.map(\.x), cz = cells.map(\.y)
        let pad = max(grow, 0) + 1
        let lo = SIMD2(Double(cx.min()!) - pad, Double(cz.min()!) - pad)
        let hi = SIMD2(Double(cx.max()!) + pad, Double(cz.max()!) + pad)
        let round = 0.28, half = SIMD2<Double>(repeating: 0.5 - round)
        let geometry = Shapes.fill(from: lo, to: hi, step: 0.25) { p in
            var near = Double.infinity
            for c in pts {
                let q = simd_abs(p - c) - half
                near = min(near, simd_length(simd_max(q, SIMD2(repeating: 0))) + min(max(q.x, q.y), 0) - round)
            }
            return grow >= 0 ? grow - near : near + grow
        }
        guard let n = Shapes.node(geometry, color, y: 0) else { return nil }
        n.position = v3(station.offset.x, y, station.offset.y)
        return n
    }

    /// The launch complex, poured as one apron: screening at the hatch, the store, the test rows and the
    /// pad, each painted on it, with a gantry beside the pad and floodlights over the yard.
    func output(_ station: Station, deckInUse: Bool) -> SetPiece? {
        guard station.hasPad else { return nil }
        var piece = SetPiece()
        let deck = deckInUse ? station.deckCells : []
        let parts: [(Area, [Cell], NSColor)] = [(.decon, station.deconCells, Self.hazard),
                                                (.storage, station.storageCells, Self.bayPaint),
                                                (.deck, deck, Self.deckPaint),
                                                (.pad, station.padCells, Self.padPaint)]
        // The apron itself, a part at a time so the pointer still finds what it is standing over, each a
        // hair over the last so the overlaps do not fight.
        for (i, (area, cells, _)) in parts.enumerated() {
            if let k = slab(cells, of: station, grow: 0.5, Self.kerb, y: -0.004) { piece.add(k, as: area) }
            if let a = slab(cells, of: station, grow: 0.36, Self.concrete, y: Kit.plateTop + Double(i) * 0.0004) {
                piece.add(a, as: area)
            }
        }
        for (area, cells, color) in parts {
            if let n = slab(cells, of: station, grow: -0.14, color, y: Kit.plateTop + 0.003) { piece.add(n, as: area) }
        }
        // A white line round the pad, and the gantry standing off its seaward corner.
        if let ring = slab(station.padCells, of: station, grow: 0.06, Self.paintLine, y: Kit.plateTop + 0.0035),
           let inner = slab(station.padCells, of: station, grow: -0.1, Self.padPaint, y: Kit.plateTop + 0.004) {
            piece.add(ring, as: .pad)
            piece.add(inner, as: .pad)
        }
        let px = station.padCells.map(\.x), pz = station.padCells.map(\.y)
        let trench = SCNNode(geometry: SCNPlane(width: 1.15, height: 1.15))
        trench.geometry!.firstMaterial = flat(NSColor(rgb: (0.16, 0.16, 0.18)))
        trench.eulerAngles.x = -.pi / 2
        trench.eulerAngles.z = .pi / 4
        trench.position = v3(station.offset.x + station.padCenter.x, Kit.plateTop + 0.005, station.offset.y + station.padCenter.y)
        piece.add(trench, as: .pad)
        let gantry = Self.gantry()
        gantry.position = v3(station.offset.x + Double(px.min()!) - 0.75, 0, station.offset.y + station.padCenter.y)
        piece.add(gantry, as: .pad)
        // Floodlights on the pad's own corners, where they would light a rocket standing on it.
        for (dx, dz) in [(Double(px.min()!) - 0.95, Double(pz.min()!) - 0.95), (Double(px.max()!) + 0.95, Double(pz.min()!) - 0.95)] {
            let mast = Self.floodlight()
            mast.position = v3(station.offset.x + dx, 0, station.offset.y + dz)
            piece.add(mast, as: .pad)
        }
        return piece
    }

    /// A service gantry: four legs braced in a lattice, a head at the top and an arm swung over the pad.
    private static func gantry() -> SCNNode {
        let n = SCNNode()
        let frame = lit(steel), dark = lit(NSColor(rgb: (0.5, 0.52, 0.55)))
        let height = 2.4, span = 0.34
        for (sx, sz) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            let leg = SCNNode(geometry: SCNBox(width: 0.07, height: height, length: 0.07, chamferRadius: 0))
            leg.geometry!.firstMaterial = frame
            leg.position = v3(sx * span, height / 2, sz * span)
            n.addChildNode(leg)
        }
        for level in 1...4 {
            let y = height * Double(level) / 4.5
            for turned in [false, true] {
                let rail = SCNNode(geometry: SCNBox(width: turned ? 0.05 : span * 2, height: 0.05, length: turned ? span * 2 : 0.05, chamferRadius: 0))
                rail.geometry!.firstMaterial = dark
                rail.position = v3(turned ? span : 0, y, turned ? 0 : span)
                n.addChildNode(rail)
                let far = rail.clone()
                far.position = v3(turned ? -span : 0, y, turned ? 0 : -span)
                n.addChildNode(far)
            }
        }
        let head = SCNNode(geometry: SCNBox(width: span * 2.3, height: 0.2, length: span * 2.3, chamferRadius: 0))
        head.geometry!.firstMaterial = frame
        head.position = v3(0, height + 0.1, 0)
        n.addChildNode(head)
        // The arm reaches out over the pad, where a rocket stands.
        let arm = SCNNode(geometry: SCNBox(width: 1.5, height: 0.09, length: 0.16, chamferRadius: 0))
        arm.geometry!.firstMaterial = dark
        arm.position = v3(0.85, height - 0.35, 0)
        n.addChildNode(arm)
        return n
    }

    /// A floodlight mast: a post with a row of lamps on its head, turned in over the yard.
    private static func floodlight() -> SCNNode {
        let n = SCNNode()
        let post = SCNNode(geometry: SCNBox(width: 0.08, height: 1.35, length: 0.08, chamferRadius: 0))
        post.geometry!.firstMaterial = lit(steel)
        post.position = v3(0, 0.675, 0)
        n.addChildNode(post)
        for i in -1...1 {
            let lamp = SCNNode(geometry: SCNBox(width: 0.16, height: 0.12, length: 0.08, chamferRadius: 0))
            lamp.geometry!.firstMaterial = flat(NSColor(rgb: (0.96, 0.95, 0.8)))
            lamp.position = v3(Double(i) * 0.18, 1.37, 0)
            n.addChildNode(lamp)
        }
        return n
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

    /// The bay: an apron outside the hull with a landing circle painted for every slot, and the airlock a
    /// marked passage running back in through it.
    func input(_ station: Station) -> SetPiece? {
        guard station.hasHangar, !station.hangarCells.isEmpty else { return nil }
        var piece = SetPiece()
        for (area, cells) in [(Area.bay, station.hangarCells), (.airlock, station.airlockCells)] {
            if let k = slab(cells, of: station, grow: 0.5, Self.kerb, y: -0.004) { piece.add(k, as: area) }
            if let a = slab(cells, of: station, grow: 0.36, Self.concrete, y: Kit.plateTop) { piece.add(a, as: area) }
        }
        if let apron = slab(station.hangarCells, of: station, grow: -0.14, Self.bayPaint, y: Kit.plateTop + 0.003) {
            piece.add(apron, as: .bay)
        }
        // The passage is marked down its middle rather than floored in a colour of its own.
        if !station.airlockCells.isEmpty {
            let xs = station.airlockCells.map(\.x), zs = station.airlockCells.map(\.y)
            let lane = SCNNode(geometry: SCNPlane(width: min(0.8, Double(xs.max()! - xs.min()!) + 0.7), height: Double(zs.max()! - zs.min()!) + 0.4))
            lane.geometry!.firstMaterial = flat(Self.hazard.darker(0.15))
            lane.eulerAngles.x = -.pi / 2
            lane.position = v3(station.offset.x + Double(xs.min()! + xs.max()!) / 2, Kit.plateTop + 0.003,
                               station.offset.y + Double(zs.min()! + zs.max()!) / 2)
            piece.add(lane, as: .airlock)
        }
        // A circle painted where each ship sets down, with its own number bar beside it.
        for slot in station.hangarSlots {
            let ring = SCNNode(geometry: SCNPlane(width: 1.18, height: 1.18))
            ring.geometry!.firstMaterial = flat(Self.paintLine)
            ring.eulerAngles.x = -.pi / 2
            ring.position = v3(station.offset.x + slot.x, Kit.plateTop + 0.004, station.offset.y + slot.y)
            piece.add(ring, as: .bay)
            let inner = SCNNode(geometry: SCNPlane(width: 1.0, height: 1.0))
            inner.geometry!.firstMaterial = flat(Self.bayPaint)
            inner.eulerAngles.x = -.pi / 2
            inner.position = v3(station.offset.x + slot.x, Kit.plateTop + 0.005, station.offset.y + slot.y)
            piece.add(inner, as: .bay)
        }
        return piece
    }

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

    /// The Cape's own pieces where the classic station's read as another era: a console of the kit's own,
    /// a shipping container for a crate, a service barrier round a release that is held, and a powered
    /// flatbed for the pallet.
    func console(color: NSColor) -> SCNNode? {
        guard let desk = Kit.prop("desk_computer", scale: 0.7, yaw: .pi, color: color) else { return nil }
        let n = SCNNode()
        desk.position = v3(0, -0.5, 0.12)
        n.addChildNode(desk)
        let screen = SCNNode(geometry: SCNBox(width: 0.26, height: 0.18, length: 0.02, chamferRadius: 0.01))
        screen.geometry!.firstMaterial = flat(color)
        screen.name = "panel"
        screen.position = v3(0, 0.02, 0.02)
        n.addChildNode(screen)
        return n
    }

    /// A shipping container: corrugated sides, a painted end in the repo's colour, and corner castings.
    func crate(color: NSColor) -> SCNNode? {
        let n = SCNNode()
        let body = SCNNode(geometry: SCNBox(width: 0.5, height: 0.26, length: 0.34, chamferRadius: 0.01))
        body.geometry!.firstMaterial = lit(color.darker(0.06))
        body.position = v3(0, 0.13, 0)
        n.addChildNode(body)
        for k in -2...2 {
            let rib = SCNNode(geometry: SCNBox(width: 0.02, height: 0.24, length: 0.35, chamferRadius: 0))
            rib.geometry!.firstMaterial = lit(color.lighter(0.1))
            rib.position = v3(Double(k) * 0.1, 0.13, 0)
            n.addChildNode(rib)
        }
        for (sx, sz) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            let casting = SCNNode(geometry: SCNBox(width: 0.07, height: 0.07, length: 0.07, chamferRadius: 0))
            casting.geometry!.firstMaterial = lit(NSColor(rgb: (0.72, 0.74, 0.78)))
            casting.position = v3(sx * 0.215, 0.235, sz * 0.135)
            n.addChildNode(casting)
        }
        return n
    }

    /// A held release is fenced with service rails and a lamp at each post, rather than tape.
    func hold(tall: Bool) -> SCNNode? {
        let n = SCNNode()
        let radius = 0.8
        for k in 0..<4 {
            let a = Double(k) / 4 * 2 * .pi + .pi / 4
            let post = SCNNode(geometry: SCNBox(width: 0.06, height: 0.4, length: 0.06, chamferRadius: 0))
            post.geometry!.firstMaterial = lit(NSColor(rgb: (0.72, 0.74, 0.78)))
            post.position = v3(cos(a) * radius, 0.2, sin(a) * radius)
            n.addChildNode(post)
            let lamp = SCNNode(geometry: SCNBox(width: 0.08, height: 0.05, length: 0.08, chamferRadius: 0.01))
            lamp.geometry!.firstMaterial = flat(NSColor(rgb: (0.98, 0.76, 0.2)))
            lamp.position = v3(cos(a) * radius, 0.44, sin(a) * radius)
            n.addChildNode(lamp)
            let b = Double(k + 1) / 4 * 2 * .pi + .pi / 4
            let from = SIMD2(cos(a) * radius, sin(a) * radius), to = SIMD2(cos(b) * radius, sin(b) * radius)
            let mid = (from + to) / 2
            for y in [0.18, 0.32] {
                let rail = SCNNode(geometry: SCNBox(width: simd_distance(from, to), height: 0.03, length: 0.03, chamferRadius: 0))
                rail.geometry!.firstMaterial = lit(NSColor(rgb: (0.84, 0.86, 0.88)))
                rail.eulerAngles.y = atan2(-(to.y - from.y), to.x - from.x)
                rail.position = v3(mid.x, y, mid.y)
                n.addChildNode(rail)
            }
        }
        return n
    }

    /// A powered flatbed: a plated deck on a chassis with a light bar, its bed where the classic one's is.
    func pallet(color: NSColor) -> SCNNode? {
        let n = SCNNode()
        let deck = SCNNode(geometry: SCNBox(width: Props.palletWidth, height: 0.05, length: Props.palletDepth, chamferRadius: 0.01))
        deck.geometry!.firstMaterial = lit(NSColor(rgb: (0.62, 0.65, 0.7)))
        n.addChildNode(deck)
        let chassis = SCNNode(geometry: SCNBox(width: Props.palletWidth - 0.14, height: 0.07, length: Props.palletDepth - 0.14, chamferRadius: 0))
        chassis.geometry!.firstMaterial = lit(NSColor(rgb: (0.32, 0.35, 0.42)))
        chassis.position = v3(0, -0.06, 0)
        n.addChildNode(chassis)
        for side in [-1.0, 1.0] {
            let stripe = SCNNode(geometry: SCNBox(width: Props.palletWidth - 0.06, height: 0.02, length: 0.04, chamferRadius: 0))
            stripe.geometry!.firstMaterial = flat(color)
            stripe.position = v3(0, 0.03, side * (Props.palletDepth / 2 - 0.03))
            n.addChildNode(stripe)
        }
        let bar = SCNNode(geometry: SCNBox(width: 0.2, height: 0.03, length: 0.05, chamferRadius: 0))
        bar.geometry!.firstMaterial = flat(NSColor(rgb: (0.98, 0.76, 0.2)))
        bar.position = v3(Props.palletWidth / 2 - 0.14, 0.05, 0)
        n.addChildNode(bar)
        return n
    }

    /// A computer desk against an outer wall of the office's farthest cell from the door, its screen
    /// turned into the room, so whoever stands on that cell stands at it.
    func dress(office room: Room, in station: Station, sign: OfficeSign) -> SCNNode? {
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
